# ai-judge 구현 계획

입력: `spec.md`, `design.md`(승인), `decisions.md` 1~72. 순서는 design.md "구현 단계 분할" 7단계를 따른다.
화면 규칙은 `docs/specs/retro-theme/design.md` 3장(구성 요소·ai-judge 대조표)을 그대로 쓴다. 같은 역할의 요소를 새로 모양 짓지 않는다.

## 공통 규칙
- 각 커밋 전: `flutter analyze` 이슈 0 + `flutter test` 전부 통과.
- **원격 DB 적용은 단계마다 오너 확인 후**(결정 72). 에이전트는 `supabase db push`, `supabase migration up`, 쓰기가 섞인 `supabase db query --linked`, `supabase storage rm`, `supabase functions deploy`, `supabase secrets set`을 실행하지 않는다. 읽기 전용(`supabase migration list --linked`, 파일 읽기)만 한다.
- 단계 순서: 로컬 구현 → analyze/test → **오너 승인 → 오너가 원격 적용 → 오너가 SQL 테스트 실행 → 통과하면 커밋.** SQL 테스트가 실패하면 고치는 마이그레이션을 새 파일로 추가한다(적용된 파일은 수정하지 않는다).
- SQL 테스트는 로컬 Docker가 없어 원격에서만 돈다. 쓰기가 있는 스모크는 마지막에 `raise exception`으로 전체 롤백하고 결과를 예외 메시지로 돌려준다. 규칙 테스트(`battle_outcome_rules.sql`)는 SELECT만 한다.
- 커밋: `<type>: <한국어 설명>` + 이유 본문 + `Co-Authored-By` 줄. 새 화면 하나 = 커밋 하나. push 없음.
- 시크릿 값은 파일·로그·커밋·보고에 쓰지 않는다. `GEMINI_API_KEY`는 이미 Supabase 시크릿으로 등록돼 있다.
- `docs/specs/retro-theme/`와 `lib/core/widgets/`·`lib/core/theme/` 공용 위젯의 기존 동작은 바꾸지 않는다. 필요한 변형은 추가만 하고 진행 기록에 적는다.

## 착수 전 확인 (2026-09-15)
- `supabase migration list --linked`: 로컬 12개 = 원격 12개(마지막 `20260910140000_battle_deadline`). 미적용 없음.
- 기준선: retro-theme 최종 상태(analyze 0, test 194).
- 작업 트리: `.claude/agent-memory/`만 미추적.

## CLAUDE.md·dev-standards와의 관계 (충돌 점검 결과)
- **오너가 이미 해소한 충돌**: CLAUDE.md "도메인 규칙"의 상호 승인·텍스트 증거·재제출·품질전 무승자·"마감은 판정을 대신한다"·품질전 포기 `disputed`, "범위 밖"의 AI 심판·푸시 알림은 spec.md "폐기되는 기존 결정" 표(오너 승인)가 대체한다. CLAUDE.md 문구 갱신은 7단계. 1~6단계 동안 CLAUDE.md 해당 문구와 코드가 어긋나는 것은 의도된 과도기다.
- **service 전용 함수의 `auth.uid()` 가드 예외**: design.md가 기존 `settle_expired_battles` 선례로 명시했다(오너 승인). 1단계에서는 이 예외를 더 넓히지 않기 위해 내부 전용 함수(`finalize_battle`, `void_battle`, `resolve_battle`)를 **SECURITY INVOKER**로 만들고 EXECUTE를 `public, anon, authenticated`에서 회수했다. SECURITY DEFINER 함수(`forfeit_battle`, `delete_account`) 안에서만 호출되므로 소유자 권한으로 실행된다. 새 SECURITY DEFINER 함수 중 가드가 없는 것은 1단계에 없다(`settle_expired_battles`는 기존 함수 재작성). Edge Function이 service_role로 직접 불러야 하는 함수는 5·6단계에서 설계대로 DEFINER + service_role grant로 만든다.
- "테스트 없이 판정 로직 수정 금지": 판정 규칙은 SQL 테스트로 덮는다(design.md "판정 로직의 위치와 테스트 대상"). 원격 적용 후 SQL 테스트가 통과해야 커밋하므로 테스트 없는 판정 로직이 커밋되지 않는다.

---

## 1단계 — 스키마·상태 전이·점수 기반 (AI 없음)

### 마이그레이션 (적용 순서대로)
1. `supabase/migrations/20260915120000_ai_judge_reset.sql` — `delete from public.battles`(cascade로 `battle_participants` 전부). 되돌릴 수 없음.
2. `supabase/migrations/20260915120100_ai_judge_schema.sql`
   - `battles.status` 체크에 `voided` 추가, `battles_finished_has_winner` 체크(finished면 winner_id not null).
   - `battle_participants`: `evidence_type`, `evidence_content`, `evidence_submitted_at`, `decision`, `decision_at` drop / `first_submitted_at`, `attempts_used`, `last_verdict`, `passed_at`, `outcome`, `score_delta_applied` add + 주석.
   - 신규 `battle_submissions`(+부분 유니크 3개, RLS select 1개), `player_stats`(RLS select 본인), `daily_battle_slots`(RLS select 본인).
   - `handle_new_user` 교체(`player_stats` 행 생성) + 기존 사용자 백필.
   - `submit_evidence(uuid,text,text)`, `decide_evidence(uuid,uuid,text)` drop.
3. `supabase/migrations/20260915120200_ai_judge_outcome_rules.sql` — 순수 함수 `speed_outcome`, `quality_outcome`, `quality_deadline_outcome`, `outcome_score_delta`(immutable, EXECUTE 회수).
4. `supabase/migrations/20260915120300_ai_judge_transitions.sql` — `finalize_battle`, `void_battle`, `resolve_battle`(invoker, EXECUTE 회수) / `forfeit_battle`, `settle_expired_battles`, `delete_account` 재작성.

1단계에 넣지 않는 것(설계 단계 배정 그대로): `min_criteria`·`superiority_criteria`·`criteria_version`(3단계 — 지금 not null로 넣으면 현재 앱의 대결 생성이 깨진다), `verdict_reason`(6단계), battles insert 정책 drop·모집 1개 인덱스(3단계), `join_battle(uuid,int)`·슬롯 insert(4단계), Storage 정책 교체(5단계), cron `ai-judge-tick`(5단계).

### SQL 테스트 (`supabase/tests/`)
- 신규 `battle_outcome_rules.sql` — design.md 필수 규칙 18케이스 + `outcome_score_delta` 5케이스. SELECT만.
- 재작성 `settle_expired_battles_smoke.sql` — 속도전 한쪽 통과·아무도 없음·error만·판정 중 대기, 품질전 한쪽 제출·제출 없음·judging 대기, 마감 전 미변경, outcome·점수·전적 카운터, disputed 0.
- 신규 `resolve_battle_smoke.sql` — 마감 전 즉시 종결 R1(시각)·R1(동률 seq)·R2·R3, 계속(통과+실패3), 역전 대기(판정 중 제출), 종결 대결 재호출 시 점수 이중 반영 없음, `void_battle`의 오늘 슬롯만 삭제·점수 불변, 종결 대결 무효화 거부.
- 신규 `forfeit_battle_smoke.sql` — 속도전·품질전 모두 finished + 상대 승 + `forfeited_by`, 점수 하한(0점 -3 → 0, applied 0), 카운터, 비참가자·종결 대결 거부.
- 재작성 `delete_account_smoke.sql` — active 대결 cancelled, 남은 상대 점수 불변, 오늘 매칭 슬롯만 반환(어제 매칭 유지), 내 제출 `object_path` null·사유 유지, 내 `player_stats`·슬롯 삭제, 묘비화.

### Dart
- `lib/features/battle/data/battle_participant.dart`: 증거·decision 필드 제거, 요약·outcome 필드 추가.
- `lib/features/battle/data/battle_repository.dart`: `submitEvidence`·`decideEvidence`·`uploadEvidencePhoto` 제거(업로드는 5단계에서 새 경로 규칙으로 다시 추가). `createEvidencePhotoUrl` 유지.
- `lib/features/battle/domain/battle_detail.dart`: 새 상태 기준 getter로 재작성(진행 중, 포기, 승/패/무/무효, 완료한 패배).
- `lib/features/battle/presentation/battle_detail_screen.dart`: 승인/이의제기·텍스트 증거·갤러리/카메라 선택 시트·제출 격차 제거, 진행 중이면 `PixelFrame.tone(info)` "준비 중" 안내, 결과 배너를 승/패/무/무효로, 포기 확인 문구 통일.
- `lib/features/battle/presentation/battle_chips.dart`: `voided` 라벨·결과 라벨 매핑 **추가만**(retro-theme가 ai-judge 몫으로 남긴 자리).
- `lib/features/profile/data/profile_repository.dart`: 기록 필터 `finished, draw, voided`.
- `lib/features/profile/domain/battle_record.dart`: 승/패/무/무효 라벨.
- `lib/features/profile/presentation/profile_screen.dart`: 유형별 요약 두 줄을 둘 다 승/패/무로(배치 그대로, 점수 표시는 7단계).
- `lib/features/auth/data/auth_repository.dart`: 사진 경로를 `battle_submissions.object_path`(본인 행)에서 조회.
- `lib/core/strings.dart`: 제거된 UI 전용 문자열 삭제, 준비 중·무효·포기 확인 문자열 추가.
- 테스트: `test/features/battle/domain/battle_detail_test.dart`, `test/features/profile/domain/battle_record_test.dart` 재작성, `test/widget_test.dart`·`test/features/battle/battle_join_vs_intro_test.dart` 가짜 저장소·상세 화면 테스트 갱신.

### 커밋 단위 (원격 적용·SQL 테스트 통과 후)
1. `feat: AI 심판 전환을 위한 대결 스키마·판정 규칙·점수 기반` — 마이그레이션 4개 + `supabase/tests/*`.
2. `feat: 대결 상세에서 상호 승인·텍스트 증거·갤러리 제거` — Dart 전체(모델·저장소·도메인·화면·테스트). 새 화면이 아니라 기존 화면 축소라 한 커밋.
   - 1과 2는 같은 원격 상태를 전제로 하므로 연달아 커밋한다(1만 원격에 있고 2가 없으면 앱이 없는 컬럼을 읽는다).

### 로컬 검증
- `flutter analyze` 이슈 0, `flutter test` 전부 통과.
- grep: `lib/`에 `decide_evidence`·`submit_evidence`·`decideEvidence`·`ImageSource.gallery`·`evidence_content` 없음, `supabase/migrations/2026091512*`에서 `'disputed'`를 쓰는(update/insert) 코드 없음.

### 원격 적용 (오너)
1. `supabase db push --dry-run` — 4개 파일만 나오는지 확인.
2. `supabase db push`
3. `supabase migration list --linked` — 16개 일치.
4. SQL 테스트(각각 결과 확인):
   - `supabase db query --linked -f supabase/tests/battle_outcome_rules.sql` → 23행 모두 `ok = true`
   - `supabase db query --linked -f supabase/tests/resolve_battle_smoke.sql` → `SMOKE RESULT ok=true`
   - `supabase db query --linked -f supabase/tests/settle_expired_battles_smoke.sql` → `ok=true`
   - `supabase db query --linked -f supabase/tests/forfeit_battle_smoke.sql` → `ok=true`
   - `supabase db query --linked -f supabase/tests/delete_account_smoke.sql` → `ok=true`
5. Storage 정리(오너 확인 후): `supabase storage rm -r ss:///battle_evidence/ --linked --experimental`
   - 버킷 자체는 남긴다(5단계에서 새 정책으로 재사용).

### 에뮬레이터 수동 확인 (원격 적용 후)
- 내 대결·대결 찾기·프로필이 오류 없이 열림(기존 대결은 모두 사라져 빈 상태).
- 두 계정으로 모집 등록 → 참가 → 대결 상세: 승인/이의제기·텍스트 입력·갤러리 선택이 없고 "준비 중" 안내만.
- 포기 → 확인 문구 "포기하면 패배로 끝나고 3점이 깎여요…" → 결과 배너 패배/승리, 프로필 기록에 승/패.
- 탈퇴(테스트 계정) → 성공, 상대 대결이 취소로 사라짐.

### 오너 할 일
- 원격 적용 승인, 위 적용·SQL 테스트·Storage 정리 명령 실행(또는 실행 허락).

---

## 2단계 — AI 데이터 제공 동의

### 파일
- 마이그레이션 `supabase/migrations/20260916120000_ai_consent.sql`: `ai_consents`, `ai_consent_events`(+RLS 본인 select), `give_ai_consent(text)`, `withdraw_ai_consent()`, `get_consent_withdrawal_impact()`, `join_battle(uuid)`에 동의 검사(`CONSENT_REQUIRED` hint) 추가, battles insert 정책을 동의 조건이 붙은 `"consented creator can create a pending battle"`로 교체, `delete_account`에 동의 기록 삭제 추가.
- SQL 테스트 `supabase/tests/ai_consent_smoke.sql`: 철회 시 active 포기(-3·상대 승)·pending 취소·슬롯 미반환·동의 행 삭제·이벤트 기록, 미동의 참가 `CONSENT_REQUIRED`, 미동의 생성 RLS 차단, 탈퇴 시 동의·이벤트 삭제, anon 권한 오류.
- Dart: `core/app_links.dart`(정책 문서 주소 상수), `features/battle/data/ai_consent.dart`·`ai_consent_repository.dart`, `domain/ai_consent_providers.dart`·`ai_consent_rules.dart`, `presentation/ai_consent_screen.dart`(신규 화면 + `ensureAiConsent`), `features/profile/presentation/ai_consent_section.dart`(프로필 섹션 + 철회 대화상자), 대결 만들기·참가 진입 시 동의 유도, `strings.dart`.
- 테스트: `test/features/battle/domain/ai_consent_rules_test.dart`(오류 코드 판별·철회 문구), `test/features/battle/ai_consent_test.dart`(동의 화면 항목, 참가·생성 유도, 철회 흐름).

### 커밋
1. `feat: AI 데이터 제공 동의 스키마와 철회 처리` (마이그레이션 + SQL 테스트)
2. `feat: AI 데이터 제공 동의 화면` (새 화면)
3. `feat: 프로필 동의 상태와 동의 철회` (프로필 섹션)

### 원격 적용 후 검증
- `supabase db query --linked -f supabase/tests/ai_consent_smoke.sql` → ok
- 에뮬레이터: 미동의 계정으로 참가 → 동의 화면, 거부 → 스낵바, 동의 → 참가 진행, 철회 → 진행 중 대결 패배 처리, 개인 투두 영향 없음.

### 오너 할 일
- 동의 문구의 개인정보처리방침 링크 URL 확정(정책 문서 게시 전이면 임시 URL 결정).

---

## 3단계 — Edge Function 공통 + 기준 생성·검사 + 대결 만들기

### 파일
- `supabase/config.toml`(신규, `[functions.judge-quality] verify_jwt = false`는 6단계에 추가 — 3단계는 파일만), `supabase/functions/_shared/{gemini,schemas,prompts,auth,errors}.ts`, `supabase/functions/battle-criteria/index.ts`, `supabase/functions/_shared/*_test.ts`.
- 마이그레이션 `supabase/migrations/20260916130000_ai_criteria.sql`: `battles`에 `min_criteria jsonb`·`superiority_criteria jsonb`(+유형 제약)·`criteria_version`, 모집 1개 부분 유니크 인덱스, insert 정책 drop(2단계에서 이름이 `"consented creator can create a pending battle"`로 바뀌었다 — 그 이름으로 drop한다), `criteria_checks`·`ai_criteria_calls`(+RLS), `begin/finish/fail_criteria_call`(service), `create_battle(uuid,int)`, `update_battle_criteria(uuid,uuid)`, `get_my_limits()`, `delete_account`에 기준 원장 삭제, 2분 넘은 `in_progress` 정리 함수.
  - `min_criteria not null`은 기존 행이 없고(1단계 정리) 앱이 같은 커밋에서 `create_battle` RPC로 바뀌므로 이 단계에서 not null로 둔다. 원격 적용과 앱 배포 사이에 옛 앱이 대결을 만들면 실패한다(배포 전이라 허용).
- SQL 테스트 `supabase/tests/criteria_smoke.sql`: 10회 산입(성공+2분 내 진행 중), 실패 미산입, 11번째 `CRITERIA_CALL_LIMIT`, `PENDING_EXISTS`, 차단/사용됨/만료/타인 check `CHECK_INVALID`, 유형별 우열 기준 제약, `update_battle_criteria` version+1·`NOT_PENDING`.
- Dart: `BattleCriteriaRepository`, `CriteriaCheckResult`, `Battle` 기준 필드, `BattleRepository.createBattle(checkId, duration)`, `create_battle_screen.dart` 2단계 교체, 기준 편집 위젯(내 모집 수정에서 재사용), `strings.dart`.

### 커밋
1. `feat: 판정 기준 원장과 기준 검사 증서 스키마`
2. `feat: Gemini 기준 생성·검사 Edge Function` (Deno 코드 + `deno test`)
3. `feat: 대결 만들기를 AI 기준 생성·승인 흐름으로 교체` (화면)
4. `feat: 내 모집 기준 수정` (내 모집 카드 → 편집 화면)

### 로컬 검증
- `deno test supabase/functions/_shared/`(Deno는 `C:\workspaces\devtools\deno`에 설치 — 설치는 오너 확인 후), analyze/test.

### 원격 적용 후 검증
- `supabase db query --linked -f supabase/tests/criteria_smoke.sql`
- 오너가 `supabase functions deploy battle-criteria` 실행 후 에뮬레이터: 속도전 최소 기준만 / 품질전 두 목록, 수정 → 재검사 → 차단(우열 기준만 증명 불가로 고쳐도 차단) → 되돌리기 → 올리기, 원장에 두 목록 재검사가 1회, 실패 호출 미산입, 미동의 시 Edge 로그에 Gemini 호출 없음.

### 오너 할 일
- `supabase functions deploy battle-criteria`, (선택) `supabase secrets set GEMINI_MODEL=...`. 키 값은 에이전트에게 전달하지 않는다.
- Deno 설치 허락.

---

## 4단계 — 모집 목록·참가·하루 1대결·상대 카드

### 파일
- 마이그레이션 `supabase/migrations/20260917120000_join_and_player_cards.sql`: `list_open_recruits()`, `join_battle(uuid,int)`(version·동의·내 슬롯·생성자 슬롯·슬롯 2행 insert) + 기존 `join_battle(uuid)` drop, `get_player_card(uuid)`, KST 날짜를 인자로 받는 내부 헬퍼(경계 테스트용), `create_battle`·`begin_criteria_call`에 오늘 슬롯 검사.
- SQL 테스트 `supabase/tests/join_battle_smoke.sql`: `CRITERIA_CHANGED`(우열 기준만 바꾼 경우 포함), `MY_DAILY_LIMIT`, `CREATOR_DAILY_LIMIT`, 양쪽 슬롯 생성, KST 자정 경계, `ALREADY_MATCHED`, 임의 사용자 `get_player_card` 거부.
- Dart: `PlayerCard`, `BattleRepository.listOpenRecruits`/`joinBattle(id, version)`/`fetchPlayerCard`, 모집 목록 카드·모집 상세 바텀시트(오류 코드 분기), 대결 상세 상대 카드. VS 인트로 연결(`maybeShowVsIntro`)은 시트의 참가 성공 경로로 옮겨 재사용.
- 테스트: 오류 코드 → 문구 매핑 유닛 테스트, `battle_join_vs_intro_test.dart`를 시트 경로로 갱신(인트로 후 토스트 순서 유지).

### 커밋
1. `feat: 하루 1대결 원장과 기준 버전 확인 참가`
2. `feat: 모집 목록 생성자 전적과 모집 상세 시트` (화면)
3. `feat: 대결 상세 상대 카드` (화면 일부)

### 원격 적용 후 검증
- `supabase db query --linked -f supabase/tests/join_battle_smoke.sql`
- 에뮬레이터(두 계정): 기준 확인 후 생성자가 수정 → 참가 시 배너와 갱신, 하루 두 번째 참가 차단 문구(유료 예고), 참가 성공 → VS 인트로 → 토스트.

---

## 5단계 — 증거 제출·속도전 판정·증거 비공개

### 착수 메모 (2026-09-16)
- 충돌 점검: 새로 생긴 충돌 없음. CLAUDE.md의 상호 승인·텍스트 증거·재제출·"마감은 판정을 대신한다"는
  spec.md "폐기되는 기존 결정" 표(오너 승인)가 대체하며 문구 갱신은 7단계다. service 전용 함수의
  `auth.uid()` 가드 예외는 기존 `settle_expired_battles` 선례와 같고 마이그레이션 주석에 이유를 적는다.
- 작업 순서: (1) 마이그레이션(Storage 정책 교체 → `accept_submission`/`record_speed_verdict`/
  `sweep_stale_submissions` → cron) → (2) `_shared` 판정 스키마·프롬프트 + `deno test` →
  (3) `submit-evidence` Edge Function → (4) SQL 스모크 → (5) Dart(모델·저장소·`BattleDetail`·화면) →
  (6) `flutter analyze`/`flutter test`.
- 5단계에서 품질전 UI는 열지 않는다. 판정 잡이 6단계라, 지금 품질전 사진을 받으면 대결이 마감까지
  판정 없이 매달린다. 서버(`accept_submission`)는 설계대로 품질전 제출 행까지 만들되, 화면은
  품질전에 한해 1단계의 "준비 중" 안내를 남긴다(속도전에서는 제거).

### 파일
- 마이그레이션 `..._speed_submissions.sql`: Storage 정책 4개 교체, `accept_submission`·`record_speed_verdict`·`sweep_stale_submissions`(service, DEFINER + service_role grant, 가드 예외 주석), cron `ai-judge-tick`(`* * * * *`, sweep만).
- `supabase/functions/submit-evidence/index.ts`(속도전 경로), `_shared` 판정 스키마·프롬프트 추가 + 테스트.
- SQL 테스트 `supabase/tests/ai_judge_flow_smoke.sql`(속도전 부분): 거부 3종 행 없음, 5회 소진 즉시 종결, 양쪽 통과 즉시 종결, error 미산입, sweep 3분, 판정 중 제출 있는 대결 settle 건너뜀, 진행 중 상대 행 0건(RLS, authenticated 위장).
- Dart: `BattleSubmission`, `BattleRepository.uploadEvidencePhoto`(`{battle}/{user}/{uuid}.jpg`, upsert 없음)·`submitEvidence`(invoke)·`fetchSubmissions`, `BattleDetail` 제출 가능/남은 횟수/잠금/판정 중 getter, 대결 상세 내 영역(카메라 전용·미리보기·제출·결과·이력)·상대 영역 요약, 1단계 "준비 중" 안내 제거.

### 커밋
1. `feat: 속도전 제출 수락·판정 기록과 증거 비공개 정책`
2. `feat: 증거 제출 Edge Function(속도전)`
3. `feat: 대결 상세 카메라 촬영 제출과 속도전 판정 결과` (화면)

### 원격 적용 후 검증
- `supabase db query --linked -f supabase/tests/ai_judge_flow_smoke.sql`
- 오너가 `supabase functions deploy submit-evidence` 후 두 계정: 진행 중 상대 사진 서명 URL 발급 실패, 합격/불합격/사유 표시(상대에게는 결과만), 10분 지난 사진 거부 문구.

---

## 6단계 — 품질전 판정 잡·자동 재시도·마감 대기

### 파일
- 마이그레이션 `..._quality_judgments.sql`: `battles.verdict_reason`, `quality_judgments`(+RLS 켬·정책 없음), `claim_quality_judgment`·`record_quality_verdict`·`record_quality_failure`·`dispatch_quality_judgments`(pg_net + Vault 이름 참조), `accept_submission` 품질전 경로, `void_battle`·`forfeit_battle`·`delete_account`에 잡 삭제, cron `ai-judge-tick`에 dispatch 추가.
- `supabase/functions/judge-quality/index.ts`, `submit-evidence`의 품질전 경로 + `EdgeRuntime.waitUntil`, `config.toml` `verify_jwt = false`.
- SQL 테스트: `ai_judge_flow_smoke.sql`에 품질전(4회 실패 → voided + 오늘 슬롯만 반환, 임대 만료 = 실패 1회, 성공 종결, 판정 중 마감 대기 후 확정).
- Dart: 품질전 제출(한 번만 확인 다이얼로그), 판정 중·무효 표시.

### 커밋
1. `feat: 품질전 판정 잡과 자동 재시도`
2. `feat: 품질전 판정 Edge Function`
3. `feat: 대결 상세 품질전 제출과 판정 대기` (화면)

### 오너 할 일
- `supabase secrets set JUDGE_CRON_SECRET=...`, Vault에 `judge_function_url`·`judge_cron_secret` 입력, `supabase functions deploy judge-quality submit-evidence`.
- 재시도 간격 관찰용으로 잠시 틀린 키를 쓸지 결정(운영 키를 바꾸는 일이라 오너 판단).

---

## 7단계 — 결과·점수·전적 표시와 정리

### 파일
- Dart: 결과 배너(부제·점수 변화·사유), 종결 후 양쪽 이력 공개, 프로필 점수 + 승/패/무(`myPlayerStatsProvider`)·무효 라벨, 내 대결 목록 상태 줄, `main_shell.dart` 프로필 탭 복귀 시 `battleRecordsProvider` invalidate, `battle_chips.dart` 결과 라벨 매핑을 outcome 기준으로(종료·미결 행 제거), 미사용 문자열 정리.
- 문서: `CLAUDE.md` 범위 밖·도메인 규칙·코딩 규칙(service 전용 함수 예외 한 줄)·개발 명령어(`supabase functions deploy`, `supabase secrets set`, `deno test`), `TODO_BACKLOG.md`.

### 커밋
1. `feat: 대결 결과 배너 점수 변화와 판정 사유` (대결 상세)
2. `feat: 프로필 점수와 승패무 전적` (프로필)
3. `feat: 내 대결 목록 상태 줄` (내 대결)
4. `docs: AI 심판 기준으로 CLAUDE.md 도메인 규칙 갱신`

### 검증
- spec 수용 기준 "결과·점수·전적", "최종성·포기", "알림 대상 정의", "데이터·문서"를 수동 체크리스트로 확인. 원격 적용 없음(스키마 변경이 생기면 그 지점에서 멈추고 확인).

---

## 진행 기록

### 5단계 (구현 완료, 원격 적용·배포·스모크 통과, 2026-09-16)
- 착수 메모의 순서대로 진행했고 중간에 바꾸지 않았다.
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` **251개 통과**(4단계 227 + 증거 제출 위젯 9 +
  `BattleDetail` 제출 판단 유닛 10 + 제출 규칙 유닛 5). `deno test supabase/functions/_shared/`
  **16개 통과**(3단계 11 + 제출 요청 경로 검증 1 + 판정 응답 검증 1 + 프롬프트 3).
- 구현 단계에서는 Gemini를 부르지 않았고 원격 DB에 쓰지 않았다(스모크는 원격 적용 뒤에 돌렸다).
- 설계와 달라진 점
  - **품질전 화면은 열지 않았다**(착수 메모). 판정 잡이 6단계라 지금 품질전 사진을 받으면 대결이
    마감까지 판정 없이 매달린다. 서버(`accept_submission`)와 `submit-evidence`는 설계대로 품질전
    제출 행까지 만들되, 화면은 품질전에 한해 "준비 중" 안내를 남겼다. 그래서 plan 5단계 파일 목록의
    "1단계 준비 중 안내 제거"는 속도전에서만 이뤄졌고, 문구는 품질전 기준으로 고쳐 썼다.
  - `record_speed_verdict`가 `{battle_status}`가 아니라 `{applied, battle_status}`를 돌려준다.
    sweep이 먼저 `error`로 내렸거나 대결이 이미 끝나 늦게 온 판정을 버린 경우를 Edge가 구분할 수 있다.
  - `accept_submission`이 경로가 `{battle_id}/{user_id}/`로 시작하는지 서버에서도 본다(Storage 정책과
    이중 검사). 업로드 정책을 우회한 경로가 제출 행으로 남지 않게 한다.
  - 마감만 지난 경우(`active`인데 `deadline_at` 경과)를 `SUBMISSION_LOCKED`가 아니라
    `DEADLINE_PASSED`로 구분해 돌려준다. 사용자에게 "왜 못 내는지"가 달라진다.
  - `MyEvidenceSection`은 `canSubmitEvidence`가 false면 촬영 버튼을 내리고, 마감이 지난 경우에만
    그 사실을 알린다(설계가 정하지 않은 지점).
  - uuid 패키지를 넣지 않고 `Random.secure()` 16바이트 hex로 파일명을 만든다(새 패키지 금지 규칙).
  - `EvidenceCamera` + `evidenceCameraProvider`를 새로 뒀다. 위젯 테스트에서 카메라를 가짜로 바꾸려면
    주입 지점이 필요하다(`vsIntroSeenStoreProvider` 선례와 같은 방식).
  - 종결 후 **양쪽** 이력 공개는 7단계 몫이라 이번에는 내 이력 + 상대 요약까지만 만들었다.
  - `sweep_stale_submissions`는 3단계에서 미뤄 둔 `ai_criteria_calls`의 2분 경과 `in_progress` 정리를
    함께 한다(설계 표 그대로).
- 위젯 테스트 메모: 미리보기 사진이 들어가면 "제출" 버튼이 기본 테스트 화면(800x600) 밖으로 밀린다.
  `ensureVisible` 없이 `tap`하면 "off-screen" 경고와 함께 실패한다.
- 1단계 위젯 테스트 두 개가 속도전에서도 "준비 중" 안내를 기대하고 있어 새 규칙(속도전은 촬영 제출,
  품질전만 준비 중)으로 고쳤다.
- 원격 적용 후 `ai_judge_flow_smoke` **`ok=t`**(마지막에 롤백하므로 원격 데이터는 그대로다).
  `if exists` 없이 drop하는 Storage 정책 4개가 실제로 원격에 있는지 먼저 확인하고 적용했다.
- `supabase functions deploy submit-evidence` 완료. 비인증 호출은 POST·GET 모두 401이다.
  Gemini 실호출은 아직 하지 않았다(에뮬레이터 수동 검증 때 처음 부른다).

### 1단계 (로컬 구현 완료, 원격 미적용·미커밋)
- 순서 변경 없음.
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` 189개 통과(retro-theme 기준선 194에서 상호 승인·텍스트 증거·제출 격차 테스트를 지우고 준비 중 안내·무효·포기 문구 통일·유형 공통 승패 테스트를 더함).
- grep 확인: `lib/`에 `decide_evidence`·`submit_evidence`·`decideEvidence`·`submitEvidence`·`ImageSource`·`evidence_content`·`'approve'`·`'dispute'` 0건. 새 마이그레이션의 `disputed`는 상태 제약·주석·RLS 읽기 조건뿐이고 쓰는 곳 없음.
- SQL 테스트는 로컬 실행 수단이 없어 **미실행**(원격 적용 후 오너가 실행).
- 위젯 테스트 수정 중 발견: 프로필 기록이 세 장이면 계정 창 버튼이 목록의 그리기 범위 밖으로 밀려 `find.text`가 못 찾음 → 테스트에서 `scrollUntilVisible`로 내려 확인(앱 동작 문제 아님).
- 설계와 달라진 점
  - 내부 전용 `finalize_battle`/`void_battle`/`resolve_battle`을 SECURITY INVOKER로 만듦(위 "충돌 점검 결과"). 앱·anon·authenticated는 부를 수 없음은 설계와 같다.
  - `battles_finished_has_winner` 체크 제약 추가: 설계의 "finished면 winner_id 항상 채워짐"을 DB가 강제. 정리 마이그레이션 뒤라 기존 행 위반 없음.
  - `resolve_battle`이 품질전 `active` 마감(Q8/Q9)도 처리하고 `settle_expired_battles`는 대상 대결마다 `resolve_battle`만 부른다(설계는 settle 안에서 품질전을 직접 처리). 규칙 적용 지점을 한 곳으로 모으려는 것이며 결과는 같다.
  - `resolve_battle`은 요약 컬럼(`attempts_used`, `passed_at`)이 아니라 `battle_submissions` 원본에서 통과 시각·횟수·판정 중 여부를 센다(요약 컬럼은 5단계 `record_speed_verdict`가 표시용으로 갱신).
  - `quality_deadline_outcome`에 양쪽 제출(원래 `judging`이어야 하는 불일치 상태)이 들어오면 모든 값을 null로 돌려 "결정하지 않음"으로 둔다 — cron이 예외로 전체 정산을 멈추지 않게.
  - `battle_outcome_rules.sql`에 설계 18케이스 외 `outcome_score_delta` 5케이스를 더해 23행.
  - 제거한 UI 전용 문자열(승인/이의제기·텍스트 증거·갤러리·제출 격차 등)을 7단계까지 미루지 않고 1단계에서 삭제. 참조가 모두 사라져 남기면 옛 규칙 문구가 되살아날 여지만 생긴다. 공용 칩이 쓰는 `battleStatusFinished`/`battleStatusDisputed`는 유지.
  - `battle_chips.dart`에 `voided` 상태 라벨과 `무효` 결과 라벨 매핑을 추가(기존 매핑 불변).

### 4단계 (구현 완료, 원격 적용·스모크 통과, 2026-09-16)
- 순서 변경 없음.
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` 227개 통과(3단계 218 + 모집 시트 위젯 7 + 오류 코드 유닛 2). Edge Function은 손대지 않아 `deno test`는 3단계 결과(11개) 그대로다.
- Gemini·원격 쓰기 없음. 읽기 전용 확인만 했다.
- 설계와 달라진 점
  - **KST 날짜를 인자로 받는 내부 헬퍼는 만들지 않았다.** `now()`를 조작할 수 없어 경계 테스트에 쓸모가 없고, 규칙 자체는 "슬롯의 `kst_date`가 오늘인가"뿐이다. 스모크에서 어제 날짜 슬롯을 가진 사용자가 오늘 참가에 성공하는 것으로 같은 의미를 덮었다(`yesterday_slot`).
  - `create_battle`·`begin_criteria_call`의 오늘 슬롯 검사는 3단계에서 이미 넣어 두어 이번에 추가 작업이 없다.
  - 도메인 `BattleRecruit`를 지우고 데이터 모델 `OpenRecruit`(+`PlayerCard`)로 바꿨다. `list_open_recruits`가 대결·기준·생성자 전적을 한 번에 주므로 provider에서 이름을 따로 붙이던 조합 단계가 사라졌다.
  - `list_open_recruits`는 `setof jsonb`를 돌려주고 각 행이 `{battle, creator}` 두 덩어리다(Dart에서 그대로 두 모델로 나뉜다).
  - **모집 목록 카드에서 참가 버튼을 없앴다.** 참가는 기준을 본 뒤 시트에서만 할 수 있다(spec "참가자는 자기가 확인한 기준으로 참가한다").
  - 시트는 참가에 성공하면 참가한 모집을 `pop`으로 돌려주고, 목록 갱신·VS 인트로·성공 토스트·탭 이동은 화면이 이어서 한다. 시트를 닫은 뒤에는 시트 context가 없어 그 안에서 인트로를 띄울 수 없다.
  - 기간 칸은 `PixelTag` + `battleStatusTagStyle('draw')`(중립 모양)을 재사용했다. retro-theme가 기간 전용 스타일을 따로 두지 않았다.
  - `get_player_card`는 탈퇴한 사용자에게 점수 자리를 null로 돌려주고, 화면은 "전적 없음"으로 보여 준다.
- VS 인트로는 `maybeShowVsIntro`/`shouldShowVsIntro`/`VsIntroSeenStore`/`displayInitial`을 그대로 재사용했다(새로 만든 것 없음). 기존 순서 테스트(인트로 → 토스트)는 시트 경로로 갱신해 그대로 통과한다.
- 위젯 테스트 메모: 모달 시트가 떠도 뒤의 목록 카드가 살아 있어 첫 기준·생성자 전적 문구가 두 번 잡힌다. 시트에만 있는 요소(우열 기준, 유형 설명, 참가 버튼)는 `findsOneWidget`으로, 겹치는 문구는 `findsWidgets`로 확인한다.
- 검토에서 고친 것 두 가지.
  - `join_battle_smoke`가 매칭 결과(`joined`·`slots_after_join`)를 A의 탈퇴 **뒤에** 읽고 있었다. 탈퇴는 그 대결을 취소하고 그날 슬롯을 반납하므로 두 항목이 항상 어긋난다. 탈퇴 전에 변수로 잡아 두도록 옮겼다.
  - `ai_consent_smoke`의 `join_battle` 호출 3곳을 2인자 시그니처로 고쳤다(직접 insert한 대결은 `criteria_version` 기본값 1).
- 참가 버튼이 사라져 쓰이지 않게 된 `battleJoin`·`battleJoinFailed` 문자열을 지웠다(오류 문구는 코드별 매핑이 대신한다).
- 원격 적용 후 `join_battle_smoke`·`ai_consent_smoke` 모두 `ok=t`. 두 스모크 다 마지막에 롤백하므로 원격 데이터는 그대로다.

### 3단계 (로컬 구현 완료, 원격 미적용·미배포·미커밋, 2026-09-16)
- 순서 변경 없음.
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` 218개 통과(2단계 201 + 기준 규칙 유닛 10 + 대결 만들기 위젯 7).
- `deno test supabase/functions/_shared/` **11개 통과**(`schemas_test.ts` 6개, `prompts_test.ts` 5개). Gemini를 부르지 않는 순수 함수 테스트다.
  - 실행 시점에 오너가 이미 Deno 2.9.6을 `C:\workspaces\devtools\deno\deno.exe`에 설치하고 CLAUDE.md 개발 명령어에 `deno test`를 적어 둔 상태였다(아직 커밋되지 않은 변경). 설치는 내가 하지 않았다.
  - PATH 등록이 실행 중인 셸에 반영되지 않아 절대 경로로 불렀다. 새 셸에서는 `deno test supabase/functions/_shared/`로 된다.
- 원격 읽기 확인: `battles` 0행 → `min_criteria`를 not null로 추가해도 안전하고, 이 마이그레이션은 기존 행을 바꾸지 않는다.
- Gemini는 한 번도 부르지 않았다(키가 Edge 환경에만 있고 배포 후 오너 승인 아래 호출한다).
- 설계와 달라진 점
  - `finish_criteria_call`·`fail_criteria_call`이 설계의 `uuid`/void 대신 **jsonb**를 돌려준다(`check_id`, `calls_left`). 남은 횟수를 알려고 Edge가 RPC를 한 번 더 부르지 않게 하려는 것이다(`get_my_limits`는 `auth.uid()` 기반이라 service 롤에서는 쓸 수 없다).
  - `finish_criteria_call`에 `p_ai_model` 인자를 더해 `criteria_checks.ai_model`에 `모델명/프롬프트버전`을 남긴다(design "프롬프트 설계 원칙" 7의 사후 추적을 기준 생성에도 적용).
  - 기준 목록 모양(1~5개, 각 1~100자)을 `is_criteria_list(jsonb)` immutable 함수로 만들어 `battles`와 `criteria_checks` 체크 제약에서 함께 쓴다(설계는 모양 검사 방법을 정하지 않았다).
  - **2분 넘은 `in_progress` 정리 함수는 만들지 않았다.** 한도 계산(`criteria_calls_used`)이 2분이 지난 `in_progress`를 세지 않으므로 한도에는 영향이 없다. 행을 `failed`로 바꾸는 청소는 설계대로 5단계 `sweep_stale_submissions`에 함께 넣는다.
  - `begin_criteria_call`의 사전 검사는 설계 표 그대로다(generate → `PENDING_EXISTS`·`MY_DAILY_LIMIT`, check+battle_id → `NOT_PENDING`). 생성 흐름 중의 재검사(battle_id 없음)는 동의와 10회 한도만 본다 — 최종 판단은 `create_battle`이 다시 한다.
  - `create_battle`은 생성용 증서만 받는다(`battle_id is not null`인 수정용 증서는 `CHECK_INVALID`). 반대로 `update_battle_criteria`는 그 대결 id가 박힌 증서만 받는다.
  - 개인정보처리방침 링크는 2단계 그대로 비워 두었다(건드리지 않음).
- 화면: 대결 만들기를 입력 → 생성 중 → 결과(읽기/수정/차단/AI 실패) 3단계로 바꿨고, 내 모집 카드에 "기준 수정"을 더했다. 모집 목록 카드의 기준 미리보기와 생성자 전적은 설계대로 4단계 몫이다.

### 2단계 (로컬 구현 완료, 원격 미적용·미커밋, 2026-09-16)
- 순서 변경 없음.
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` 201개 통과(1단계 189 + 동의 규칙 유닛 5 + 동의 위젯 7).
- 원격 읽기 확인(`supabase db query --linked "select status, count(*) ..."`): `battles` 0행. 동의 제도가 생기기 전에 만들어진 모집(= 생성자가 동의하지 않은 모집)이 없으므로 **이 마이그레이션은 기존 행을 지우거나 바꾸지 않는다.** 이후에는 insert 정책(동의 필요)과 철회 시 모집 취소가 "모집 중 대결의 생성자는 항상 동의 상태"를 유지한다.
- SQL 스모크(`ai_consent_smoke.sql`)는 로컬 실행 수단이 없어 **미실행**(원격 적용 후 오너가 실행). `%%` 대신 `ok=% %` 형식을 썼다.
- 설계와 달라진 점
  - **개인정보처리방침 링크**: 정책 문서가 아직 게시되지 않아 주소가 없다. `lib/core/app_links.dart`의 `privacyPolicyUrl`을 빈 문자열로 두고, 비어 있으면 동의 화면에서 링크 영역을 그리지 않는다. 주소를 채우면 복사할 수 있는 글자로 보여 준다 — `url_launcher`가 pubspec에 없어 브라우저 열기는 넣지 않았다(패키지 추가는 오너 판단).
  - **battles insert 정책**: 3단계에서 drop될 정책이지만 그때까지 동의 없이 만든 모집이 생기면 안 되므로, drop 대신 동의 조건을 붙인 `"consented creator can create a pending battle"`로 교체했다. 정책 위반은 `CONSENT_REQUIRED` 힌트가 아니라 RLS 오류(42501)로 떨어진다 — 앱은 생성 화면에 들어가기 전에 동의를 확인하므로 정상 경로에서는 보이지 않는다.
  - **철회 구현**: 포기 규칙을 복제하지 않으려고 `withdraw_ai_consent`가 대결마다 기존 `forfeit_battle`을 그대로 부른다. 잠금 순서는 "내 동의 행 → 내 대결"이고 `join_battle`도 같은 순서라 교착이 없다. 모집 취소를 먼저 하고 진행 중 대결을 나중에 처리해, 그 사이에 매칭된 대결도 포기로 잡힌다.
  - **동의 기록이 없을 때의 철회**: `CONSENT_REQUIRED` 힌트로 거부한다(설계에 명시되지 않은 지점).
  - 프로필 동의 섹션은 계정 섹션 **위**에 둔다(design.md 화면 2 그대로).
- 위젯 테스트에서 배운 것: 조회가 끝나지 않은 대화상자에는 `PixelLoader`가 계속 돌아 `pumpAndSettle`이 끝나지 않는다(`pump`로 확인). 프로필에 섹션이 하나 늘어 계정 창이 첫 화면 밖으로 밀리므로 탈퇴 테스트도 `scrollUntilVisible`이 필요하다.

## 1단계 원격 적용 기록 (2026-09-15)
- 오너 승인 후 `supabase db push`로 마이그레이션 4개 적용. `supabase migration list --linked` 16개 일치.
- 적용 전 원격 데이터: 대결 4, 참가자 8, 증거 사진 6, 활성 프로필 3. 적용 후 대결·참가자 0, `player_stats` 3행 백필.
- `battle_outcome_rules.sql` 23케이스 + 요약 전부 `ok=true`.
- 스모크 4개는 처음에 `RAISE` 문구의 `%%`(퍼센트 글자)가 값 자리로 인식되지 않아 컴파일 오류로 한 줄도 실행되지 않았다. `ok=% %`로 고친 뒤 4개 모두 `ok=t`, 롤백 후 잔여 행 0 확인.
- **증거 사진 6장이 버킷에 남아 있다.** `supabase storage rm`(버킷 경로 `-r`, 파일 경로 지정 둘 다)이 오류 없이 `deleted: []`로 끝났다. SQL 직접 삭제는 `storage.protect_delete()`가 막는다. 어느 대결에도 연결되지 않아 앱에는 보이지 않는다. 오너가 대시보드 Storage 화면에서 지우거나 5단계 Storage 정책 교체 때 함께 정리한다.

## 3단계 배포와 첫 실호출 기록 (2026-09-16)
- `supabase functions deploy battle-criteria` 완료. 상태 ACTIVE, `verify_jwt = true`.
- 토큰 없이 함수를 부르면 401로 거부되는 것을 확인했다.
- 오너가 허용해 에뮬레이터에서 AI 데이터 제공 동의를 눌렀다(`ai_consents` 1행, 이력 `given`).
- 첫 실호출: 품질전, 제목 "clean the desk completely"(에뮬레이터 입력기가 한글을 넣지 못해 영문).
  - 화면에 최소 기준 3개와 우열 기준 3개가 한국어로 나왔다. 두 목록이 서로 다른 관점이었다
    (최소: 물건·먼지·얼룩 없음 / 우열: 광택, 다리·프레임, 주변 공간).
  - `ai_criteria_calls` 1행 `succeeded`, `criteria_checks` 1행, `provable = true`,
    `ai_model = gemini-2.5-flash/p1`.
  - "이 기준으로 올리기"는 누르지 않고 빠져나왔다. 대결 0건, 증서는 미사용 상태로 남았다(24시간 뒤 만료).
- CLI에는 함수 로그 명령이 없다(list/delete/download/deploy/new/serve뿐). 로그는 대시보드에서 본다.
- 아직 확인하지 않은 것: 증명 불가 미션 차단, 기준 수정 후 재검사, 하루 10회 한도 도달, 모집 1개 제한.
