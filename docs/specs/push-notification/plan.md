# push-notification 구현 계획

입력: `spec.md`, `design.md`(둘 다 오너 승인). 순서는 design.md "구현 단계 분할" 7단계를 그대로 따른다.
선례 형식·운영 규칙은 `docs/specs/ai-judge/plan.md`를 따른다.

## 공통 규칙
- 각 커밋 전: `flutter analyze` 이슈 0 + `flutter test` 전부 통과. TypeScript를 건드린 단계는 `deno test supabase/functions/_shared/`도.
- **원격 DB 적용은 단계마다 오너 확인 후.** 에이전트는 `supabase db push`, `supabase migration up`, 쓰기·DDL이 섞인 `supabase db query --linked`, `supabase functions deploy`, `supabase secrets set`, Vault 접근을 실행하지 않는다. 읽기 전용(`supabase migration list --linked`, 파일 읽기)만 한다.
- 단계 순서: 로컬 구현 → analyze/test → **오너 승인 → 오너가 원격 적용 → 오너가 SQL 테스트 실행 → 통과하면 커밋.** SQL 테스트가 실패하면 고치는 마이그레이션을 **새 파일로** 추가한다(이미 적용된 파일은 수정하지 않는다).
- SQL 스모크는 로컬 Docker가 없어 원격에서만 돈다. 쓰기가 있는 스모크는 마지막에 `raise exception`으로 전체를 롤백하고 결과를 예외 메시지(`SMOKE RESULT ok=...`)로 돌려준다.
- 커밋: `<type>: <한국어 설명>` + 이유 본문 + `Co-Authored-By` 줄. 새 화면 하나 = 커밋 하나. push 없음.
- 시크릿 값은 파일·로그·커밋·보고에 쓰지 않는다. 이름만 참조한다(`FCM_SERVICE_ACCOUNT`, `NOTIFY_CRON_SECRET`, Vault `notify_function_url`·`notify_cron_secret`).
- Firebase·FCM·Google OAuth를 에이전트가 호출하지 않는다. 실발송 확인은 오너 몫이다.

## 착수 전 확인 (2026-09-17)
- 기준선: `flutter analyze` 이슈 0, `flutter test` 273개 통과(ai-judge 7단계 상태).
- 마이그레이션 로컬 21개, 마지막이 `20260919120000_quality_judgments.sql`. 이번 1단계가 22번째다.
- 이름 충돌 없음: `device_push_tokens`·`notification_outbox`·`enqueue_notification`·`register_push_token`이 `supabase/`·`lib/`에 하나도 없다(첫 배선).
- 작업 트리: `.claude/agent-memory/`, `docs/specs/push-notification/`만 미추적.

## CLAUDE.md·dev-standards와의 관계 (충돌 점검 결과)
설계와 프로젝트 규칙을 대조한 결과 **구현을 멈춰야 하는 충돌은 없다.** 확인한 항목:
- CLAUDE.md "범위"는 푸시 알림(`push-notification`)을 배포 전 별도 feature로 이미 인정한다. 도메인 규칙(상태 전이·판정·점수·하루 1대결)은 이 feature가 한 줄도 바꾸지 않는다.
- 사용자 FK는 `public.profiles`, RLS는 테이블 생성과 같이, 앱 RPC는 `revoke ... from public, anon` + `grant ... to authenticated` + 로그인 가드, 참가자 검사는 `is distinct from` — 모두 설계가 그대로 따른다.
- service·cron 전용 함수의 `auth.uid()` 가드 예외는 CLAUDE.md 코딩 규칙에 **이미 명시된 예외**다(`settle_expired_battles` 선례). 해당 함수 주석에 이유를 적는다.
- **의도된 예외 2건은 design이 7단계에 CLAUDE.md 갱신을 배정해 해소한다**(임의 판단이 아니다):
  1. 알림 문구를 `lib/core/strings.dart`가 아니라 서버(`_shared/notification_text.ts`)에 둔다 — 앱이 종료된 상태에서도 시스템이 그려야 한다. 1단계는 문구를 만들지 않으므로 이 단계와는 무관하다.
  2. 알림 발송 실패는 토스트 없이 서버 로그만 남긴다 — 사용자가 할 수 있는 일이 없고 그 시점에 앱을 보고 있지 않다(VS 인트로 예외와 같은 성격).
- **`enqueue_notification`이 예외를 삼키는 것은 "에러를 삼키지 않는다"와 어긋나지 않는다.** 그 규칙은 로그를 남기고 사용자에게 알리라는 것이고, 이 함수는 `raise warning`으로 서버 로그를 남긴다. 토스트를 띄우지 않는 근거가 위 예외 2다. 알림 때문에 판정·점수 트랜잭션이 롤백되는 것이 더 큰 규칙 위반이다(design 원칙 2).

---

## 1단계 — 기기 알림 토큰과 알림 발송 원장 스키마 (스키마 변경 있음)

### 파일
1. `supabase/migrations/20260920120000_push_tokens_and_outbox.sql` (신규)
   - `device_push_tokens` — `token` PK(소유자 교체용), `user_id` → `public.profiles`, `created_at`, `last_seen_at`, `(user_id)` 인덱스. RLS 켜고 **select 본인 행만**, insert/update/delete 정책 없음(쓰기는 RPC만).
   - `notification_outbox` — `id bigserial`, `recipient_id` → `profiles`, `kind`(7종 체크), `battle_id` → `battles`, `dedup_key`, `payload jsonb`, `status`(pending/sending/sent/failed/dropped), `attempts`, `lease_until`, `last_error`, `created_at`, `sent_at`, `unique (recipient_id, dedup_key)`, `pending` 부분 인덱스. RLS 켜고 **정책 하나도 두지 않는다**(선례 `quality_judgments`).
   - `enqueue_notification(uuid, text, uuid, text, jsonb)` — invoker, EXECUTE 전부 회수. `on conflict do nothing` + **내부 예외 블록 + `raise warning`**(design 원칙 2).
   - `register_push_token(text)` / `unregister_push_token(text)` — 앱용. 로그인 가드 + anon 회수 + authenticated 부여.
   - `claim_notifications(integer)` / `record_notification_result(bigint, text, text, text[])` — Edge 전용. 로그인 가드 대신 `authenticated`까지 회수하고 `service_role`만 부여, 주석에 예외 이유.
   - `delete_account()` **재정의** — **20260919120000의 최신 정의를 기반으로** 내 토큰·내 수신 원장 삭제 단계만 추가. 인자 없는 시그니처 유지, `create or replace`.
2. `supabase/tests/push_token_smoke.sql` (신규) — design 1단계 검증 목록 전체.

이 단계에 넣지 않는 것(설계 배정 그대로): 사건 지점 enqueue 배선(3단계), `dispatch_notifications`·cron `notify-tick`·Edge·Vault(4단계), `enqueue_deadline_reminders`(6단계), Dart·Firebase 배선(2단계). **1단계만 적용해도 앱 동작은 전혀 바뀌지 않는다 — 아무도 원장에 넣지 않는다.**

### 커밋
- `feat: 기기 알림 토큰과 알림 발송 원장 스키마` — 마이그레이션 1개 + 스모크 1개. Dart 변경 없음.

### 로컬 검증
- `flutter analyze` 이슈 0, `flutter test` 전부 통과(Dart를 건드리지 않아도 확인한다).
- grep: 새 이름 4종이 `lib/`에 없음(클라이언트는 2단계부터 쓴다).

### 원격 적용 (오너)
1. `supabase db push --dry-run` — `20260920120000_push_tokens_and_outbox.sql` 1개만 나오는지 확인.
2. `supabase db push`
3. `supabase migration list --linked` — 22개 일치.
4. `supabase db query --linked -f supabase/tests/push_token_smoke.sql` → `SMOKE RESULT ok=true`
5. 회귀(`delete_account`를 고쳤으므로): `delete_account_smoke.sql`, `ai_consent_smoke.sql`, `criteria_smoke.sql`, `join_battle_smoke.sql` → 각각 `ok=true`.

### 검증 항목 (스모크가 덮는 것 = design 1단계 목록)
토큰 upsert(1행·`last_seen_at` 갱신), 소유자 교체, 본인 삭제, 남의 토큰은 `unregister`로 지워지지 않음, 탈퇴 시 토큰·수신 원장 삭제, 남의 토큰 select 0행, 원장은 authenticated에게 0행, 토큰 직접 insert 차단, anon RPC 권한 오류, enqueue 중복 1행(첫 payload 유지), 잘못된 kind를 넣어도 예외가 밖으로 나오지 않음(삼킴 확인), claim 후 두 번째 claim 0행, 토큰 없는 수신자 `dropped`, 마감 지난 `deadline_soon` `dropped`, `record_notification_result`의 `sent`·죽은 토큰 정리.

---

## 2단계 — 클라이언트 Firebase 배선·권한·토큰 등록/해제 (스키마 변경 없음)
- 파일: `pubspec.yaml`(`firebase_core`, `firebase_messaging`), `android/settings.gradle.kts`·`android/app/build.gradle.kts`·`AndroidManifest.xml`(POST_NOTIFICATIONS + 알림 아이콘 meta-data), `android/app/google-services.json`(**오너**), `tool/generate_launcher_icons.dart`(흰색 실루엣 추가), `lib/main.dart`, `lib/core/push/{push_messaging,push_repository,notification_payload,push_service,push_providers}.dart`, `lib/core/navigation/main_shell.dart`, `lib/features/battle/presentation/{battle_recruits_screen,create_battle_screen}.dart`, `lib/features/profile/presentation/{profile_screen,notification_section}.dart`, `lib/features/auth/data/auth_repository.dart`, `lib/core/strings.dart`.
- 커밋: `feat: FCM 수신 배선과 알림 권한 요청` / `feat: 프로필 알림 꺼짐 안내`(화면이라 따로).
- 검증: `flutter test`(가짜 `pushMessagingProvider`로 기존 위젯 테스트 통과 포함), 실기기에서 첫 참가·첫 생성 직후 권한 다이얼로그 1회·거부해도 전 기능 동작, 허용 시 `device_push_tokens` 1행, 로그아웃 시 그 행 사라짐, 두 기기 로그인 시 2행(오너 확인).

## 3단계 — 사건 지점 enqueue (스키마 변경 있음)
- 파일: `supabase/migrations/..._notification_events.sql`(`join_battle`·`finalize_battle`·`void_battle`·`accept_submission`(**인자 시그니처 유지**)·`record_speed_verdict`·`delete_account` 재정의), `supabase/tests/notification_events_smoke.sql`.
- 커밋: `feat: 대결 사건에서 알림 원장 적재`.
- 검증: N2가 판정·포기·마감 정산 세 경로 모두에서 양쪽 1행씩·중복 없음·포기 본인 제외, N4가 `error`·종결 트랜잭션에서 없음, N3가 속도전·이미 제출한 사람에게 없음, N5 `slot_returned` 분기, payload에 `reason`·`object_path`·`display_name` 키 없음, enqueue가 실패해도 종결·점수가 커밋됨.

## 4단계 — 발송 경로 (스키마 변경 있음)
- 파일: `supabase/migrations/..._notification_dispatch.sql`(`dispatch_notifications`, cron `notify-tick` 등록), `supabase/functions/send-notifications/index.ts`, `supabase/functions/_shared/{fcm.ts,notification_text.ts}` + `*_test.ts`, `supabase/config.toml`(`verify_jwt = false`).
- 커밋: `feat: 알림 발송 Edge Function과 발송 주기 작업`.
- 검증: `deno test`(문구 6종·프라이버시 금지 항목 부재·점수 0 문장·남은 시간 표기·FCM 요청 조립·죽은 토큰 판별·시크릿 불일치 401), 오너가 시크릿·Vault 입력 후 배포 → 실발송 확인, 원장이 `sent`로 바뀜, 잘못된 토큰이 정리됨.

## 5단계 — 알림 탭과 포그라운드 (스키마 변경 없음)
- 파일: `lib/core/push/{push_service,notification_payload,push_providers}.dart`, `lib/core/navigation/main_shell.dart`.
- 커밋: `feat: 알림 탭으로 대결 상세 열기`.
- 검증: 유닛(payload 파싱), 위젯(pending 값 유무), 실기기 백그라운드·종료 상태 탭, 취소된 대결 탭 시 오류 화면 없음, 포그라운드 수신 시 목록 갱신.

## 6단계 — N6 마감 임박 (스키마 변경 있음)
- 파일: `supabase/migrations/..._deadline_reminders.sql`(`enqueue_deadline_reminders`, `notify-tick` 명령 문자열 갱신), `supabase/tests/deadline_reminder_smoke.sql`.
- 커밋: `feat: 마감 임박 알림`.
- 검증: 대상 6케이스, 두 번째 실행 0행(한 번만), 마감 지난 `pending`은 `dropped`, 6시간 문턱 경계.

## 7단계 — 문서·배포 준비 (스키마 변경 없음)
- 파일: `CLAUDE.md`(범위 안 문구 정리 + 코딩 규칙 예외 2줄 + 개발 명령어), `DEPLOY.md`, `TODO_BACKLOG.md`.
- 저장소 밖(오너): 개인정보처리방침, Play Console 데이터 보안 양식.
- 원장 보존과 방침 보유 기간의 정합 확인(design 결정 3의 조건).

---

## 진행 기록

### 1단계 (구현 완료, 원격 적용·스모크 통과, 2026-09-17)
- 원격 적용 후 스모크 5개 전부 `ok=t`. 신규 `push_token_smoke`와, `delete_account`를 고쳤으므로 회귀 4개(`delete_account`·`ai_consent`·`criteria`·`join_battle`)를 함께 돌렸다. 모든 스모크는 마지막에 롤백해 원격 데이터는 그대로다.
- 오너가 `google-services.json`을 `android/app/`에 두었다(패키지명 `com.todododo.todododo`, 프로젝트 `tododo-f81f0`). 시크릿이 아니라 앱에 포함돼 배포되는 공개 설정이므로 저장소에 함께 둔다 — 2단계 커밋에 들어간다.
- 위 순서대로 진행했고 중간에 바꾸지 않았다.
- **Dart 변경 없음**(설계대로). 마이그레이션 1개 + 스모크 1개만 추가했다. 구현 중에는 원격 DB에 쓰기·DDL을 실행하지 않았고, 배포·시크릿·Vault·Firebase/FCM 호출도 없다.
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` **273개 통과**(기준선과 동일 — Dart를 건드리지 않았으므로 숫자가 변하지 않는 것이 정상이다). TypeScript를 건드리지 않아 `deno test`는 실행하지 않았다.
- `delete_account`는 **가장 늦은 마이그레이션(20260919120000)의 정의를 그대로 복사한 뒤** 7번 단계(알림 토큰·수신 원장 삭제)만 끼워 넣고 뒤 단계 번호를 밀었다. 기존 동작(취소 대결 슬롯 반환, 품질전 잡 삭제, 투두, 증거 경로 null, 슬롯·점수, 기준 증서·호출 원장, 동의·이력, 묘비화, `auth.users` 삭제)은 한 줄도 빠지지 않았다. 인자 없는 시그니처를 유지했다.
- 설계와 달라진 점
  - **`record_notification_result`가 `status = 'sending'`인 행만 고친다.** design은 이 조건을 적지 않았지만, 임대가 만료돼 이미 `failed`로 내려간 행에 늦게 도착한 결과가 `sent`를 덮어쓰면 "한 사건은 한 번만"의 기록이 흔들린다. ai-judge의 "늦게 도착한 판정은 조용히 버린다"와 같은 처리다.
  - **`claim_notifications`가 `p_limit`을 `greatest(coalesce(p_limit, 50), 1)`로 정규화한다.** null·0·음수로 불려도 질의가 깨지지 않게 하는 방어로, design이 정하지 않은 지점이다.
  - **`enqueue_notification`이 `p_recipient_id`·`p_battle_id`가 null이면 조용히 반환한다.** 3단계에서 `opponent_id`가 null인 모집 등 "받을 사람이 없는" 경로가 실수로 불려도 warning 로그만 쌓이지 않게 하려는 것이다(원장에는 아무 일도 하지 않는다는 점은 같다).
  - **`record_notification_result`는 `sent`/`failed`만 받는다**(design의 기록 대상 그대로). `dropped`는 `claim_notifications`가 정하는 상태라 Edge가 지정할 수 없게 두고, 알 수 없는 값은 예외로 막는다.
  - 스모크에 design 목록 밖 2건을 더했다: 잘못된 `kind`로 enqueue해도 예외가 밖으로 나오지 않는지(원칙 2의 핵심 장치라 1단계에서 바로 덮는 것이 맞다), 마감이 지난 `deadline_soon`이 `dropped`가 되는지(`claim_notifications`에 그 분기를 이미 구현했으므로 함께 본다).
- 함정 메모
  - 스모크에서 `delete_account` 같은 파괴적 호출 **뒤에** 상태를 읽으면 항상 어긋난다. U의 토큰 수·원장 수는 탈퇴 **전에** 변수로 잡아 두고 비교한다(ai-judge 4단계에서 실제로 났던 버그).
  - `RAISE`의 `%%`는 리터럴 퍼센트라 자리표시자가 되지 않는다. `'SMOKE RESULT ok=% %'` 형태를 쓴다.
  - `public.battles` 직접 insert에는 `min_criteria`가 필수고, 속도전은 `superiority_criteria`가 null이어야 한다(`battles_superiority_by_type`). 한 사람당 `pending` 모집은 1개라 스모크는 전부 `active`로 만든다.
  - RLS를 확인하려면 `set local role authenticated`가 필요하다. `do $$` 블록은 postgres(테이블 소유자)로 돌아 정책을 건너뛴다.
  - 파일 생성은 Bash 히어독이 아니라 파일 쓰기 도구로 했다. 이 환경에서 히어독은 줄바꿈이 CRLF로 전달돼 종료 표시를 못 찾고 깨진다.
