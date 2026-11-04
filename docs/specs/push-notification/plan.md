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
**2026-11-03에 범위를 고쳤다**(오너 결정). 아래는 고친 뒤의 내용이고, 근거는 `spec.md`·`design.md`의 "mutual-judge 반영" 절이다. 옛 계획은 `record_speed_verdict`에 N4를 붙이는 것이었는데 그 함수는 `20260922120000_judging_window.sql`이 삭제했다.
- 파일: `supabase/migrations/..._notification_events.sql`(`join_battle`·`finalize_battle`·`void_battle`·`accept_submission`(**인자 시그니처 유지**)·`open_judging_window`·`delete_account` 재정의 + kind CHECK 제약 교체 + `claim_notifications`에 `judge_turn` 폐기 조건), `supabase/tests/notification_events_smoke.sql`.
- 커밋: `feat: 대결 사건에서 알림 원장 적재`.
- 검증: N2가 판정·포기·마감 정산 세 경로 모두에서 양쪽 1행씩·중복 없음·포기 본인 제외, N4'가 판정할 증거가 있는 쪽에만·종결 뒤에는 `dropped`, N3가 판정 창이 열린 제출에는 없음·교체 제출로 두 번 생기지 않음, N5 `slot_returned` 분기, payload에 `reason`·`object_path`·`display_name` 키 없음, enqueue가 실패해도 종결·점수가 커밋됨.

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

### 2단계 (구현 완료, 커밋됨, 2026-11-03)
- 커밋 2개: `feat: FCM 수신 배선과 알림 권한 요청`(bef8ce2), `feat: 프로필 알림 꺼짐 안내`(a568c34).
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` **427개 통과**(기준선 409 + 신규 18),
  `flutter build apk --debug` 성공(google-services 4.5.0 + AGP 9.1.0 조합 확인, `minSdk`는 Flutter
  기본값 24라 손대지 않았다).
- 설계와 달라진 점
  - **`google-services.json`을 커밋하지 않았다.** design은 "커밋한다"였지만 `.gitignore`에
    2026-09-28 오너 결정으로 이미 들어가 있어 그쪽을 따랐다. 파일은 오너 기기의 `android/app/`에
    있고 빌드도 그것으로 통과했다. 다른 기기에서 빌드하려면 Firebase 콘솔에서 다시 받아야 한다.
  - **firebase_messaging 17이 `getToken`/`onTokenRefresh`/`deleteToken`을 deprecated로 두었다.**
    새 API(`register()`+`onRegistered`)는 등록 토큰이 아니라 FID를 스트림으로만 내줘 설계의 서버
    계약(FCM v1 `message.token`)과 "앱 실행 시 즉시 등록"이 둘 다 달라진다. `// ignore:
    deprecated_member_use` + 이유 주석으로 등록 토큰을 유지했고 전환은 `TODO_BACKLOG.md`에 남겼다.
  - **로그아웃의 토큰 정리에 5초 상한을 두었다.** 로그아웃 버튼에 진행 표시가 없어 네트워크가
    느리면 "눌러도 아무 일이 없다"로 보인다. 설계에 없던 값이고, 넘겨서 남은 토큰 행은 다음 발송에서
    죽은 토큰으로 판별돼 서버가 지운다.
  - `pendingBattleOpenProvider`와 메시지 스트림은 만들지 않았다. 5단계가 쓸 것이라 지금 넣으면
    아무도 읽지 않는 코드가 된다(`notification_payload.dart`는 plan의 2단계 파일 목록에 있어 순수
    함수와 유닛 테스트만 먼저 만들어 두었다).
- 함정 메모
  - **`Override` 타입은 `package:flutter_riverpod/flutter_riverpod.dart`에 없다.** riverpod 3에서는
    `package:flutter_riverpod/misc.dart`에 있다. 테스트 헬퍼(`test/core/push/push_fakes.dart`)가 쓴다.
  - **푸시 provider를 override하지 않은 위젯 테스트는 조용히 더러워진다.** `pushRepositoryProvider`가
    `supabase`를 만져 Supabase 미초기화 테스트에서 던지고, `PushService`가 그것을 로그로 삼킨다 —
    통과하지만 아무것도 검증되지 않는다. `MainShell`·`ProfileScreen`·참가 성공 경로를 띄우는
    테스트에는 `...pushOverrides()`를 넣는다.
  - 알림 작은 아이콘은 16셀 그림이라 24dp 캔버스에 정수 셀로 들어가지 않는다. 캔버스를
    `16 * cell`로 두어 밀도마다 채우는 비율을 같게 맞췄다(xhdpi·xxxhdpi만 표준 크기와 정확히 일치).

### 3단계 (구현 완료, 원격 적용·스모크 통과, 2026-11-04)
- **착수 직후 문서가 낡은 것을 발견해 오너에게 물었고, 추천안 3건을 모두 승인받았다**(위 "2026-11-03에
  범위를 고쳤다" 참고). spec·design의 사건 지점 표가 ai-judge 시절 기준이라 N4의 발생 지점
  `record_speed_verdict`가 이미 삭제된 함수였다. 결정 내용은 spec.md·design.md의 "mutual-judge 반영"
  절에 근거와 함께 적었다.
- 적용 순서대로 진행했다: 원장 0행 확인 → `db push --dry-run`(1개) → `db push` →
  `migration list --linked` 28개 일치 → 스모크. 중간에 바꾸지 않았다.
- 스모크 결과: 신규 `notification_events_smoke` 포함 **14개 전부 `ok=t`**
  (`push_token`·`delete_account`·`join_battle`·`mutual_judge_flow`·`settle_expired_battles`·
  `ai_consent`·`criteria`·`ai_rejudgment`·`forfeit_battle`·`custom_duration`·`recruit_browse`·
  `resolve_battle`·`ai_judge_flow`, 그리고 `mutual_judge_rules` 40행 전부 `ok: true`).
  모든 스모크는 마지막에 롤백해 원격 데이터는 그대로다(적용 뒤 원장 0행·토큰 0행 확인).
- **적용 전에 롤백 검증을 먼저 했다.** `begin;` + 마이그레이션 + 스모크를 한 파일로 이어 붙여
  `db query --linked -f`로 돌리면 스모크 끝의 `raise exception`이 전체를 되돌린다. 문법·동작을
  다 보면서 원격 스키마를 건드리지 않는 방법이라, 스키마 변경 단계에서 다시 쓸 만하다
  (검증 뒤 제약·함수 정의·`schema_migrations` 이력이 그대로인지 확인했다).
- `flutter analyze` 이슈 0, `flutter test` 427개 통과(Dart 변경 없음 — 숫자가 2단계와 같은 것이 정상).
  TypeScript를 건드리지 않아 `deno test`는 돌리지 않았다.
- 설계와 달라진 점
  - **`claim_notifications`에 `judge_turn` 폐기 조건을 더했다.** 창이 열린 직후 양쪽이 바로 판정해
    버리면 1분 뒤 tick이 집을 때 대결은 이미 끝나 있다. `deadline_soon`과 같은 성격이라 같은 자리에
    뒀다(1단계 설계에는 없던 조건).
  - **`accept_submission`은 판정 창이 열리는 제출에 N3를 보내지 않는다.** 같은 순간에 "상대가
    냈어요"와 "판정할 차례예요"가 두 줄로 쌓인다 — design 결정 1·2와 같은 처리다.
  - N1 payload의 `deadline_at`은 update의 `returning`으로 받는다. 마감 계산식이 코드에 한 번만
    있게 하려는 것이다.
- 함정 메모
  - **`battles_create_participants` 트리거가 생성자의 `battle_participants` 행을 이미 만든다.**
    스모크에서 대결을 직접 insert한 뒤 생성자 행을 또 넣으면 PK 중복으로 죽는다. 상대 행만 넣는다.
  - **kind 이름을 바꾸면 1단계 스모크도 같이 고쳐야 한다**(`quality_submitted`→`submitted`,
    `'qsub:'`→`'sub:'`). `enqueue_notification`이 CHECK 위반을 삼키므로 행이 조용히 안 생기고,
    기대값이 `null`로 어긋나야 비로소 드러난다.
  - **`push_token_smoke`의 `a_outbox_kept`가 2에서 3으로 늘었다.** 그 스모크의 탈퇴 사용자 U의
    대결 상대가 A라서 3단계부터 N5 `cancelled` 한 행이 A에게 더 생긴다. 의도된 동작이다 —
    1단계 스모크가 3단계 동작을 모르고 쓰인 것이라 기대값을 올렸다.

### 4단계 (구현 완료, 원격 적용·스모크 통과, 2026-11-04)
- 적용 순서대로: `db push --dry-run`(1개) → `db push` → `migration list --linked` 29개 일치 →
  스모크 6개 전부 `ok=t`(`notification_dispatch`·`notification_events`·`push_token`·
  `settle_expired_battles`·`mutual_judge_flow`·`delete_account`). cron 작업 4개 전부 1분·active 확인.
- `deno test supabase/functions/_shared/` **49개 통과**(기존 25 + 신규 24).
  `flutter analyze` 이슈 0(Dart 변경 없음), `deno check`로 Edge 함수 타입 확인.
- **적용해도 알림은 아직 나가지 않는다.** Vault 값이 없으면 `dispatch_notifications`가 0을
  반환하고 아무것도 보내지 않으며, 원장은 그대로 쌓여 값이 들어온 순간부터 이어서 나간다.
  남은 것은 오너 작업 네 가지(서비스 계정 키 → `FCM_SERVICE_ACCOUNT` → `NOTIFY_CRON_SECRET`·Vault
  두 항목 → `functions deploy send-notifications`)와 그 뒤의 실발송 확인이다.
- 설계와 달라진 점
  - **자격 증명이 없으면 원장을 집어 오지 않는다.** design의 실행 흐름은 "시크릿 검사 →
    claim_notifications"였는데, 그 순서면 FCM 자격 증명이 없을 때 집어 온 행이 `sending`으로
    바뀌었다가 임대 만료로 `failed`가 되어 **영영 전달되지 않는다.** 값이 들어온 뒤 쌓여 있던
    알림이 그대로 나가려면 claim 자체를 건너뛰어야 한다(200 + `skipped: true`로 답한다).
  - **응답은 `{claimed, sent, failed}`다.** design이 적은 `dropped`는 `claim_notifications` 안에서
    결정돼 Edge에 돌아오지 않으므로 셀 수가 없다.
  - **문구 두 종을 새로 썼다.** design의 문구 표는 ai-judge 시절이라 N4(속도전 합격/불합격)만
    있고 `judge_turn`이 없었고, N3도 품질전 문장 하나뿐이었다. 같은 말투로 더했다 —
    판정 차례: "판정할 차례예요 / 「제목」 24시간 안에 판정하지 않으면 자동 승인돼요",
    속도전 제출: "「제목」 이제 내 사진은 바꿀 수 없어요"(교체가 잠기는 것이 이 유형의 손해다).
  - **`completed_loss`인데 점수 변화가 0이면 "감점이 줄었어요"를 붙이지 않는다.** 점수 하한 0에
    걸린 경우라 그 말이 사실과 어긋난다.
  - 문구 함수는 **아는 키만 읽는다.** 금지 항목을 걸러내는 목록을 두지 않고 구조로 막았다 —
    payload에 `reason`·`object_path`·`display_name`이 섞여 들어와도 문구에 닿을 길이 없다(테스트로 고정).
- 함정 메모
  - **`service_role`의 EXECUTE는 `revoke ... from public, anon, authenticated`로 빠지지 않는다.**
    Supabase가 기본으로 모든 함수에 준다 — cron 전용 선례(`settle_expired_battles`·
    `dispatch_ai_judgments`·`close_expired_judging_windows`)도 전부 `service_role`에 execute가 있다.
    스모크에서 "service_role에 없음"을 기대하면 틀린다. "선례와 같은 모양인가"로 본다.
  - Deno 2.9/TS 6에서 `crypto.subtle.importKey('pkcs8', ...)`에 `Uint8Array`를 그대로 넘기면
    `ArrayBufferLike` 때문에 타입 검사가 깨진다. `new Uint8Array(new ArrayBuffer(n))`로 만들고
    반환 타입을 `Uint8Array<ArrayBuffer>`로 적는다.
