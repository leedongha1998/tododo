# push-notification 설계

## 참고
- spec.md: `docs/specs/push-notification/spec.md` (오너 승인 완료, 이 설계의 유일한 요구사항). 알림 대상 표 N1~N6, "N6의 제약", 결정 사항 5건, 수용 기준, 범위 밖이 기준이다.
- 선례: `docs/specs/ai-judge/design.md`(상태 전이·서버 전용 함수 권한·pg_net·Vault·Edge 계약·단계 분할), `docs/specs/ai-judge/plan.md`(실제 구현 결과와 함정), `docs/specs/ai-judge/spec.md` "P1. 알림 대상 사건 정의"(이 feature로 인계된 목록), `decisions.md` 21.
- 근거로 읽은 현재 구현: `supabase/migrations/20260915120100`(`battle_submissions`·`player_stats`·`daily_battle_slots`), `20260915120300`(`finalize_battle`·`void_battle`·`resolve_battle`·`settle_expired_battles`·`delete_account`), `20260917120000`(`join_battle`), `20260918120000`(`accept_submission`·`record_speed_verdict`·`sweep_stale_submissions`·cron), `20260919120000`(`quality_judgments`·`dispatch_quality_judgments`·`void_battle`·`forfeit_battle`·`delete_account`·cron), `supabase/functions/{judge-quality,submit-evidence,_shared/*}`, `supabase/config.toml`, `supabase/tests/*.sql`, `lib/core/{strings.dart,navigation/*}`, `lib/features/battle/**`, `lib/features/profile/presentation/profile_screen.dart`, `lib/features/auth/**`, `pubspec.yaml`, `android/{settings.gradle.kts,app/build.gradle.kts,app/src/main/AndroidManifest.xml}`, `DEPLOY.md`, `TODO_BACKLOG.md`.
- 저장소에 Firebase 관련 파일·패키지·권한 선언은 하나도 없다. 이번이 첫 Firebase 배선이다.

## 설계 원칙 (전체를 관통하는 4가지)

1. **알림은 이미 확정된 사실의 사본이다.** 알림 코드는 어떤 상태도 바꾸지 않고, 승패·점수·상태 전이를 읽기만 한다. 사건 지점에서 하는 일은 원장(outbox) 한 행 insert뿐이다. 판정 규칙은 ai-judge가 만든 DB 순수 함수·`finalize_battle`에 그대로 남는다(CLAUDE.md "판정 로직은 DB 또는 Edge Function", "클라이언트에서 승패 계산 금지").
2. **발송은 대결 진행을 절대 막지 못한다.** 두 겹으로 막는다. (a) 사건 트랜잭션 안에서는 HTTP를 부르지 않는다 — insert만 한다. (b) 그 insert조차 `enqueue_notification` 안의 예외 블록(= 서브트랜잭션)에서 삼키고 `raise warning`으로만 남긴다. 알림 원장이 깨져도 판정·종결·점수는 커밋된다. 발송 주기 작업도 판정 주기 작업과 **다른 cron 작업**이라 트랜잭션을 공유하지 않는다.
3. **한 사건은 한 번만 알린다.** 원장의 `unique (recipient_id, dedup_key)`가 물리적으로 막는다. 종결(N2)은 판정·포기·마감 정산 세 경로가 모두 `finalize_battle` 한 곳을 지나므로 발송 지점도 그 한 곳이고, 무효는 `void_battle` 한 곳이다.
4. **잠금화면에 나갈 수 있는 것만 원장에 담는다.** 판정 사유(`battle_submissions.reason`, `battles.verdict_reason`), 사진 경로, 상대 표시 이름은 payload에 **넣지 않는다**. 진행 중에도 상대에게 공개되는 정보(제출 여부, 속도전 합격/불합격)와 본인 결과·점수 변화만 담는다(ai-judge design 원칙 3과 같은 선).

## 발송 경로 — 기존 구조 재사용 검토

이미 검증된 경로: `pg_net` + Vault(`judge_function_url`, `judge_cron_secret`) + cron `ai-judge-tick`(1분) → `net.http_post` → Edge(`verify_jwt = false`, 헤더 `x-judge-secret` 상수 시간 비교가 유일한 관문).

| 후보 | 내용 | 채택 | 이유 |
|---|---|---|---|
| A | 사건 함수(DB) 안에서 `net.http_post`로 FCM 직접 호출 | ✗ | FCM HTTP v1은 서비스 계정으로 만든 OAuth2 액세스 토큰이 필요하다. SQL에서 RS256 JWT 서명·토큰 교환·캐시를 할 수 없다(레거시 서버 키 방식은 폐지). 원칙 2의 "트랜잭션 안 HTTP 없음"도 깨진다 |
| B | 사건 지점은 원장에 넣고, cron이 Edge를 부르고 Edge가 FCM으로 보낸다 | **✓** | 사건이 확정되는 지점이 DB 함수·Edge·cron에 흩어져 있는데(아래 표) 원장 insert는 그 **모든 경로에서 똑같이 한 줄**이다. HTTP는 트랜잭션 밖으로 완전히 빠지고, 자격 증명은 Edge에만 있다 |
| C | Edge(`submit-evidence`)가 응답 뒤 `waitUntil`로 직접 FCM 발송 | ✗ | 사건의 절반 이상이 Edge를 거치지 않는다(`join_battle`·`forfeit_battle`·`delete_account` RPC, `settle_expired_battles` cron). 두 가지 발송 수단이 생기고 중복 방지가 두 곳으로 갈라진다 |

**결론: 구조(pg_net + Vault + 상수 시간 시크릿 + `verify_jwt = false`)는 그대로 재사용하고, 대상만 새 Edge Function `send-notifications`로 둔다.** 재사용/신규 판단의 근거:

| 항목 | 판단 | 이유 |
|---|---|---|
| pg_net 확장 | 재사용 | 이미 설치·검증됨(6단계 원격 적용). 추가 작업 없음 |
| Vault에 URL·시크릿을 이름으로만 두는 방식 | 재사용 | 값을 마이그레이션·코드·로그에 남기지 않는 유일한 검증된 방법 |
| `_shared/secret.ts`의 `constantTimeEquals` | 재사용 | 같은 관문 구조. 새로 만들지 않는다 |
| Edge Function | **신규** `send-notifications` | `judge-quality`는 대결 하나의 판정 실행기다. 알림은 원장을 비우는 소비자이고 FCM 자격 증명까지 들고 있어 역할이 다르다 |
| Vault 시크릿 이름 | **신규** `notify_function_url`, `notify_cron_secret` | 함수가 다르면 URL이 다르다. 시크릿도 분리해 알림 쪽 값을 교체할 때 판정 쪽을 배포하지 않는다(관문이 곧 유일한 보안 경계라 공유하지 않는다) |
| cron 작업 | **신규** `notify-tick`(1분) | `ai-judge-tick`에 문장을 덧붙이면 같은 명령 문자열 = 같은 트랜잭션이라, 알림 쪽 예외가 `sweep_stale_submissions`의 결과까지 롤백시킨다. 원칙 2에 정면으로 어긋나므로 작업을 나눈다. `settle-expired-battles`(5분)도 그대로 둔다 |

## 알림 사건과 발송 지점

| # | 사건 | 받는 사람 | 원장에 넣는 지점 | 넣지 않는 조건 | 우선순위 |
|---|---|---|---|---|---|
| N1 | 모집에 상대가 참가(매칭) | 생성자 | `join_battle` (참가자 insert 뒤, 같은 트랜잭션) | - | P0 |
| N2 | 종결과 결과(승/패/무) | 양쪽 | `finalize_battle` (outcome·`score_delta_applied` 기록 뒤) | **포기한 본인**(`battles.forfeited_by = recipient`) — 내 행동의 결과는 알리지 않는다 | P0 |
| N2' | 종결과 결과(무효) | 양쪽 | `void_battle` | - | P0 |
| N3 | 품질전: 상대가 사진 제출 | 상대 | `accept_submission` (품질전 분기, 제출 행 생성 뒤) | 속도전(spec 결정 2), 받는 사람이 **이미 제출한 경우**(결정 사항 1 — 두 번째 사진은 곧 판정 시작이라 알리지 않는다) | P0 |
| N4 | 속도전: 상대 제출의 합격/불합격 | 상대 | `record_speed_verdict` (`resolve_battle` 반환 뒤) | `verdict = 'error'`(AI 실패는 알리지 않는다), `applied = false`(늦게 도착한 판정), **그 트랜잭션에서 대결이 종결된 경우**(결정 사항 2 — N2가 결과·점수까지 담으므로 N4를 생략한다) | P1 |
| N5 | 상대 탈퇴로 대결 취소 | 남은 사람 | `delete_account` (대결 `cancelled` + 슬롯 반환 뒤) | 상대가 없는 `pending` 모집(알릴 사람이 없다) | P1 |
| N6 | 마감 임박인데 아직 완료 못 함 | 해당 참가자 | cron `notify-tick` → `enqueue_deadline_reminders()` | 아래 "N6" 절 | P1 |

종결 세 경로가 한 지점으로 모이는 것을 확인한 결과(현재 코드 기준):

| 종결 경로 | 실제 호출 사슬 | N2 발송 지점 |
|---|---|---|
| 속도전 판정 | Edge `submit-evidence` → `record_speed_verdict` → `resolve_battle` → `finalize_battle` | `finalize_battle` |
| 품질전 판정 | Edge `judge-quality`/`submit-evidence` → `record_quality_verdict` → `finalize_battle` | `finalize_battle` |
| 품질전 재시도 소진 | `fail_quality_judgment` → `void_battle` | `void_battle` |
| 포기·동의 철회 | `forfeit_battle`(또는 `withdraw_ai_consent` → `forfeit_battle`) → `finalize_battle` | `finalize_battle` |
| 마감 정산 | cron → `settle_expired_battles` → `resolve_battle` → `finalize_battle` | `finalize_battle` |
| 탈퇴 취소 | `delete_account` (finalize를 거치지 않는다) | N5로 따로 넣는다 |

즉 **알림을 붙이는 함수는 여섯 개**(`join_battle`, `finalize_battle`, `void_battle`, `accept_submission`, `record_speed_verdict`, `delete_account`) + cron 하나다. 어느 함수에서도 규칙 판단을 새로 하지 않는다 — 이미 계산된 `outcome`/`status`/`score_delta_applied`/`verdict`를 읽어 담을 뿐이다.

## 중복 방지

`notification_outbox`의 `unique (recipient_id, dedup_key)` + 모든 insert에 `on conflict do nothing`.

| kind | dedup_key | 같은 키가 두 번 생길 수 있는 경우 | 결과 |
|---|---|---|---|
| `matched` | `matched:<battle_id>` | 없음 | - |
| `finished` | `finished:<battle_id>` | 늦게 도착한 판정이 종결된 대결에 다시 들어오는 경우, 마감 cron과 판정이 겹치는 경우 | 두 번째는 무시 |
| `quality_submitted` | `qsub:<battle_id>` | 품질전 제출은 1인 1회라 없음 | - |
| `speed_verdict` | `verdict:<submission_id>` | 없음(제출 행 하나에 판정 한 번) | 제출마다 다른 키이므로 5회 제출은 5건이 정상이다 |
| `cancelled` | `cancelled:<battle_id>` | 없음 | - |
| `deadline_soon` | `deadline:<battle_id>` | cron이 1분마다 같은 대결을 다시 본다 | **두 번째부터 전부 무시 → N6의 "한 사람당 한 번"이 여기서 보장된다** |

원장 행은 발송 뒤에도 지우지 않는다(`status`만 바뀐다). 그래서 dedup_key가 계속 살아 있어 "이미 보냈다"가 영구히 남는다. 대결당 최대 행 수는 참가자 2명 × (matched/finished/qsub 또는 verdict 5건/deadline) ≈ 15행 미만이고, 무료 사용자는 하루 1대결이라 증가량이 작다. **행을 지우는 정리 작업은 두지 않는다**(결정 사항 3) — 지우는 순간 dedup_key가 사라져 "한 사건은 한 번만"이 깨지기 때문이다.

## N6 마감 임박 — spec이 design에 넘긴 두 지점

**(1) 언제 보내는가: 마감 6시간 전 고정.** `deadline_at - interval '6 hours' <= now() < deadline_at`.

| 안 | 1일 | 3일 | 7일 | 평가 |
|---|---|---|---|---|
| 고정 6시간 전 (**채택**) | 매칭 18h 후 | 66h 후 | 162h 후 | "임박"의 뜻이 기간과 무관하게 같다. 매칭 직후가 아니고, 잠든 사이에 와도 깨어나 사진을 찍을 여유가 남는다 |
| 고정 3시간 전 | 21h 후 | 69h 후 | 165h 후 | 밤에 도착하면 아침에는 이미 마감이다. "낼 시간이 남을 만큼 이르다"를 만족하지 못할 수 있다 |
| 기간의 25% 남았을 때 | 6h 전 | 18h 전 | **42h 전** | 7일 대결에서 이틀 가까이 남은 시점에 "마감이 다가온다"고 하면 사실과 어긋나고, 그 뒤로는 알림이 없어 정작 마감 때 손해를 못 막는다 |

기간 최소값이 24시간이라 6시간 문턱이 매칭 시점보다 앞서는 경우는 없다. cron이 1분 주기라 실제 발송은 마감 6시간~5시간 59분 전 사이다.

**(2) 어느 주기 작업에 붙이는가: 신규 cron `notify-tick`(1분)의 첫 문장.** `settle-expired-battles`(5분)에 붙이지 않는 이유는 위 표의 트랜잭션 공유 문제와 같다 — 알림 판단에서 예외가 나면 그 tick의 마감 정산이 롤백된다. `ai-judge-tick`도 같은 이유로 제외한다. 1분 주기를 쓰는 이유는 6시간 문턱의 정확도를 ±1분으로 묶고, 발송(`dispatch_notifications`)과 같은 작업에 두어 임박 알림이 쌓인 즉시 나가게 하기 위함이다.

**대상 선별**(`enqueue_deadline_reminders`, spec "N6의 제약"을 SQL 조건으로 옮긴 것):

| 제약 | 조건 |
|---|---|
| 이미 종결된 대결 제외 | `b.status = 'active'` (품질전 `judging`은 양쪽 제출이 끝난 상태이므로 여기서 자동 제외된다) |
| 마감 뒤 도착 금지 | `b.deadline_at > now()`이고 발송 직전에 한 번 더 확인 — 지나 있으면 `dropped` |
| 임박 | `b.deadline_at <= now() + interval '6 hours'` |
| 품질전: 아직 제출하지 않은 참가자 | `not exists(battle_submissions where status = 'submitted' and user_id = 참가자)` |
| 속도전: 아직 통과하지 못한 참가자(불합격만 쌓인 사람 포함) | `not exists(... status = 'passed' ...)` |
| 속도전 5회 소진 제외 | `count(status in ('passed','failed')) < 5` |
| 한 사람당 한 번 | `dedup_key = 'deadline:<battle_id>'` + `on conflict do nothing` |
| 재촉하지 않는다 | 문구는 "마감까지 N시간 남았어요"까지만(아래 문구 표) |

판정 중(`judging`)인 속도전 제출이 있는 참가자는 **대상이다**. 그 제출이 불합격일 수 있고, 그러면 그대로 마감되면 손해를 본다. 발송 시각과 제출 시각이 겹쳐 "이미 냈는데 왔다"고 느낄 수 있지만, 속도전은 통과해야 완료이므로 사실과 어긋나지 않는다.

## 알림 문구

**문구는 서버(Edge)가 만든다.** 근거: 앱이 종료된 상태에서도 잠금화면에 보여야 하므로 FCM `notification` 페이로드로 보내고, 그 텍스트는 안드로이드 시스템이 앱 코드 없이 그린다. 클라이언트가 문구를 만들려면 data-only 메시지 + 백그라운드 isolate + 로컬 알림 패키지가 필요해 패키지와 실패 지점만 늘어난다. 그래서 **`lib/core/strings.dart`에는 알림 문구를 두지 않고**, `supabase/functions/_shared/notification_text.ts` 한 파일에 모아 `deno test`로 덮는다. CLAUDE.md "사용자에게 보이는 문자열은 `strings.dart`"에 대한 예외이므로 그 사실을 CLAUDE.md 코딩 규칙에 한 줄 적는다(7단계). 앱 화면에 보이는 문자열(프로필 알림 안내 등)은 종전대로 `strings.dart`다.

제목 안의 대결 제목은 `「」`로 감싼다. 남은 시간은 발송 시각 기준으로 Edge가 계산한다(원장에는 `deadline_at`만 담는다).

| # | 제목 | 본문 | 분기 |
|---|---|---|---|
| N1 | 대결이 시작됐어요 | 「{제목}」에 상대가 참가했어요. 마감까지 {N}시간 남았어요. | 1시간 미만이면 "{N}분 남았어요" |
| N2 승 | 이겼어요! | 「{제목}」 · +{delta}점 | |
| N2 완료한 패배 | 졌어요 | 「{제목}」 · {delta}점 · 기준을 통과해서 감점이 줄었어요. | 속도전 `completed_loss`만 |
| N2 패 | 졌어요 | 「{제목}」 · {delta}점 | |
| N2 포기로 인한 패배 | — | — | 포기한 본인에게는 보내지 않는다 |
| N2 무 | 무승부예요 | 「{제목}」 · {delta}점 | |
| N2 점수 변화 0 | (위와 같음) | 「{제목}」 · 점수 변화 없음 · 점수는 0점 아래로 내려가지 않아요. | `score_delta_applied = 0`일 때 문장을 바꿔 사실과 어긋나지 않게 한다 |
| N2' 무효 | 판정이 무효가 됐어요 | 「{제목}」 점수와 전적에 반영되지 않아요. | |
| N3 | 상대가 사진을 냈어요 | 「{제목}」 아직 내 사진을 내지 않았어요. | |
| N4 합격 | 상대가 기준을 통과했어요 | 「{제목}」 마감 전에 기준을 통과하면 감점이 줄어요. | |
| N4 불합격 | 상대가 불합격했어요 | 「{제목}」 | |
| N5 | 대결이 취소됐어요 | 「{제목}」 상대가 탈퇴해서 취소됐어요. 오늘 대결 한도가 돌아왔어요. | 슬롯이 반환되지 않았으면(매칭일이 오늘이 아니면) 뒷문장을 뺀다 — `payload.slot_returned` |
| N6 | 마감이 다가와요 | 「{제목}」 마감까지 {N}시간 남았어요. | |

문구가 지키는 것(테스트로 확인): 판정 사유 없음, 이미지 없음, 상대 표시 이름 없음, 내부 코드·서버 오류 메시지 없음, 전부 한국어, 누적 점수·승패 카운터 없음(결과와 이번 점수 변화까지만).

## 데이터 모델

### `device_push_tokens` (신규)
```
token text primary key                  -- FCM 등록 토큰(앱 설치 단위로 유일)
user_id uuid not null references public.profiles (id) on delete cascade
created_at timestamptz not null default now()
last_seen_at timestamptz not null default now()
index (user_id)
```
- `token`을 PK로 두는 이유: 같은 기기에 다른 계정으로 로그인하면 같은 토큰이 다시 등록된다. PK + `on conflict (token) do update set user_id = ..., last_seen_at = now()`로 **소유자가 교체**되므로, 기기를 물려준 사람에게 남의 알림이 가는 일이 없다.
- 한 계정 여러 기기 = `user_id`가 같은 행 여러 개. "주 기기" 개념을 만들지 않는다(spec).
- 사용자 FK는 `public.profiles`다(CLAUDE.md). 탈퇴는 profiles 행을 묘비로 남기므로 cascade가 돌지 않아 `delete_account`에서 명시적으로 지운다.
- `last_seen_at`은 앱이 열릴 때마다 등록 RPC가 갱신한다. 발송 실패로 지우지 못한 토큰의 원인 추적용이고, 이 값으로 만료를 판단하지는 않는다(만료 판단은 FCM 응답이 한다).
- 플랫폼 컬럼은 두지 않는다 — 안드로이드만이다(CLAUDE.md "iOS 대응 금지", 미래 대비 추상화 금지).
- RLS: 켠다. `select`는 본인 행만(`user_id = auth.uid()`). insert/update/delete 정책은 두지 않는다 → 쓰기는 아래 RPC만(선례: `ai_consents`).

### `notification_outbox` (신규)
```
id bigserial primary key
recipient_id uuid not null references public.profiles (id) on delete cascade
kind text not null check (kind in
  ('matched','finished','voided','quality_submitted','speed_verdict','cancelled','deadline_soon'))
battle_id uuid not null references public.battles (id) on delete cascade
dedup_key text not null
payload jsonb not null
status text not null default 'pending'
  check (status in ('pending','sending','sent','failed','dropped'))
attempts smallint not null default 0
lease_until timestamptz
last_error text
created_at timestamptz not null default now()
sent_at timestamptz
unique (recipient_id, dedup_key)
index (created_at) where status = 'pending'
```
- RLS: 켜고 **정책을 하나도 두지 않는다**(선례: `quality_judgments`). 서버 전용 함수만 만진다. 앱 안 알림함·읽음 표시는 spec 범위 밖이므로 클라이언트가 이 테이블을 읽을 이유가 없다.
- `status` 뜻: `pending` 발송 대기 / `sending` 임대 중 / `sent` 최소 한 기기에 전달 / `failed` 시도했으나 실패(재시도하지 않는다) / `dropped` 보낼 이유가 사라짐(토큰 없음, 마감 지난 N6, 종결된 대결의 N6).
- payload는 사건이 확정되는 트랜잭션에서 만든 **스냅샷**이다. Edge가 DB를 다시 읽지 않으므로 발송 시점에 값이 바뀌어도 문구가 흔들리지 않고, Edge가 대결·제출 테이블에 접근할 이유가 없어 비공개 정보가 새는 경로 자체가 없다.

| kind | payload 키 | 담지 않는 것 |
|---|---|---|
| `matched` | `title`, `battle_type`, `deadline_at` | 참가자 이름 |
| `finished` | `title`, `battle_type`, `outcome`(win/completed_loss/loss/forfeit/draw), `score_delta`(=`score_delta_applied`) | `winner_id`, 상대 이름, `verdict_reason` |
| `voided` | `title`, `battle_type` | 실패 원인·사유 |
| `quality_submitted` | `title` | 사진 경로, 제출 시각의 상세 |
| `speed_verdict` | `title`, `verdict`(passed/failed) | **판정 사유**, 사진 경로 |
| `cancelled` | `title`, `slot_returned`(boolean) | 탈퇴한 사람의 이름 |
| `deadline_soon` | `title`, `battle_type`, `deadline_at` | 상대의 진행 상황 |

### 기존 테이블·함수 변경
| 대상 | 변경 |
|---|---|
| `battles`, `battle_participants`, `battle_submissions`, `player_stats` | **변경 없음.** 문구에 필요한 값이 모두 이미 있다(`title`, `type`, `deadline_at`, `outcome`, `score_delta_applied`, 제출 상태) |
| `join_battle(uuid,int)` | `create or replace`로 N1 enqueue 한 줄 추가 |
| `finalize_battle` | outcome·점수 기록 루프 뒤 N2 enqueue(포기한 본인 제외) |
| `void_battle` | 무효 기록 뒤 N2' enqueue |
| `accept_submission` | 품질전 분기에 N3 enqueue(**인자 시그니처 유지** — 6단계 함정 그대로. 시그니처가 바뀌면 배포된 `submit-evidence`가 옛 오버로드를 계속 부른다) |
| `record_speed_verdict` | `resolve_battle` 반환값을 보고 N4 enqueue |
| `delete_account` | 취소된 대결마다 N5 enqueue, 내 `device_push_tokens` 삭제, 내 `notification_outbox` 행 삭제 |
| cron | 신규 작업 `notify-tick`(`* * * * *`). 기존 `ai-judge-tick`·`settle-expired-battles`는 손대지 않는다 |
| `pg_net` 확장 | 이미 설치됨. 재생성하지 않는다 |

## API 계약

### 공통 규칙 (CLAUDE.md 코딩 규칙 그대로)
- 앱이 부르는 RPC: `security definer set search_path = public`, 첫 줄 `if auth.uid() is null then raise exception '로그인이 필요합니다.'`, `revoke execute ... from public, anon` + `grant execute ... to authenticated`.
- service·cron 전용 함수: `auth.uid()` 가드 대신 `revoke execute ... from public, anon, authenticated` + (Edge가 부르는 것만) `grant execute ... to service_role`. cron만 부르는 함수는 service_role에도 주지 않는다(선례: `sweep_stale_submissions`, `dispatch_quality_judgments`). 각 함수 주석에 이 예외의 이유를 적는다.
- 내부 전용 함수(`enqueue_notification`)는 `security invoker`로 두고 EXECUTE를 전부 회수한다(선례: `finalize_battle`).
- 참가자 검사는 `is distinct from`. 새 오류 코드는 만들지 않는다 — Edge는 기존 `UNAUTHORIZED`/`BAD_REQUEST`/`SERVER_ERROR`만 쓴다.

### RPC — 앱이 호출 (authenticated)
| 함수 | 파라미터 | 반환 | 핵심 동작 |
|---|---|---|---|
| `register_push_token` | `p_token text` | void | 로그인 가드 → 형식 검사(비어 있지 않고 4096자 이하) → `insert ... on conflict (token) do update set user_id = auth.uid(), last_seen_at = now()`. 멱등이라 앱이 열릴 때마다 불러도 된다 |
| `unregister_push_token` | `p_token text` | void | 로그인 가드 → `delete where token = p_token and user_id = auth.uid()`. 로그아웃 직전에 부른다(세션이 살아 있어야 한다) |

### RPC — 서버 전용
| 함수 | 호출자 | 권한 | 역할 |
|---|---|---|---|
| `enqueue_notification(p_recipient_id uuid, p_kind text, p_battle_id uuid, p_dedup_key text, p_payload jsonb)` | 사건 함수 6개 | invoker, EXECUTE 전부 회수 | `insert ... on conflict (recipient_id, dedup_key) do nothing`. **전체를 `begin ... exception when others then raise warning ...; end;`로 감싼다** — 알림 때문에 판정 트랜잭션이 되돌아가지 않게 하는 핵심 장치 |
| `claim_notifications(p_limit integer default 50)` | Edge `send-notifications` | definer, service_role만 | (1) 임대 만료된 `sending` → `failed`(재시도 없음), (2) 보낼 이유가 사라진 `pending` → `dropped`(수신자 토큰 0개 / `deadline_soon`인데 대결이 `active`가 아니거나 마감 경과), (3) 남은 `pending`을 `for update skip locked`로 잡아 `sending`·`attempts+1`·`lease_until = now() + 2분` 기록 후 `[{id, kind, payload, tokens[]}]` 반환 |
| `record_notification_result(p_id bigint, p_status text, p_error text, p_dead_tokens text[])` | 같음 | definer, service_role만 | `sent`(+`sent_at`) 또는 `failed`(+`last_error`) 기록, `p_dead_tokens`의 행을 `device_push_tokens`에서 삭제 |
| `enqueue_deadline_reminders()` | cron `notify-tick` | definer, EXECUTE 전부 회수 | 위 "N6 대상 선별" 조건으로 `deadline_soon` 행을 쌓고 새로 쌓은 수를 반환 |
| `dispatch_notifications()` | cron `notify-tick` | definer, EXECUTE 전부 회수 | Vault에서 `notify_function_url`·`notify_cron_secret`을 읽어 `net.http_post`로 Edge를 한 번 깨운다. **값이 없으면 아무것도 보내지 않고 0을 반환**(선례: `dispatch_quality_judgments`). `pending`이 0이면 호출도 하지 않는다 |

`claim_notifications`가 "토큰 0개면 `dropped`"를 하는 이유: 알림을 거부했거나 로그아웃한 사용자의 행이 영원히 `pending`으로 남으면 tick마다 다시 집어 든다. 권한이 없는 사용자에게 보내려다 생기는 오류가 사용자에게 노출되지 않는다는 spec 수용 기준도 이 지점에서 지켜진다 — 애초에 발송을 시도하지 않는다.

### Edge Function
| 함수 | verify_jwt | 관문 | 입력 | 출력 |
|---|---|---|---|---|
| `send-notifications` | **off** (cron 전용) | 헤더 `x-notify-secret`을 시크릿 `NOTIFY_CRON_SECRET`과 `constantTimeEquals` 비교, 불일치 401 | `{}` (본문 없음. 큐를 비우는 것이 일이다) | 200 `{claimed, sent, failed, dropped}` |

`supabase/config.toml`에 `[functions.send-notifications] verify_jwt = false`를 추가한다.

실행 흐름
1. 시크릿 검사 → `claim_notifications(50)`.
2. 행마다 `notification_text.ts`로 `{title, body}`를 만든다.
3. 토큰마다 FCM HTTP v1 발송(`_shared/fcm.ts`). 한 기기라도 성공하면 그 행은 `sent`.
4. 죽은 토큰을 모아 `record_notification_result`로 한 번에 기록·정리.
5. 어떤 실패도 예외로 올리지 않고 `console.error`로만 남긴다(spec: 사용자에게 알리지 않고 서버 로그에만).

### `_shared/fcm.ts` (신규)
- 엔드포인트: `POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`.
- 인증: 서비스 계정으로 만든 OAuth2 액세스 토큰. `FCM_SERVICE_ACCOUNT`(base64 JSON)를 디코드해 `client_email`·`private_key`·`project_id`를 얻고, WebCrypto(`importKey` pkcs8 → `RSASSA-PKCS1-v1_5` SHA-256)로 JWT를 서명해 `https://oauth2.googleapis.com/token`에서 교환한다. **새 의존성 없음**(`gemini.ts`가 REST를 직접 부르는 선례와 같다). 토큰은 모듈 스코프에 만료 1분 전까지 캐시한다.
- 메시지 본문
```json
{ "message": {
    "token": "<기기 토큰>",
    "notification": { "title": "...", "body": "..." },
    "android": { "priority": "high" },
    "data": { "battle_id": "<uuid>", "kind": "finished" } } }
```
  `notification`을 쓰는 이유는 앱이 종료돼 있어도 시스템이 표시해 주기 때문이다. `android.priority = high`는 Doze 상태에서 임박·종결 알림이 늦게 도착하는 것을 막기 위함이다. 알림 채널은 따로 만들지 않고 FCM 기본 채널을 쓴다(spec 범위 밖: 여러 채널·중요도 체계). 기기 설정에서 채널 이름이 기본값으로 보이는 것은 감수한다.
- 타임아웃 10초(`AbortController`), 재시도 없음.
- 응답 해석: `404`/`UNREGISTERED`, `400`+`INVALID_ARGUMENT`(토큰 형식) → **죽은 토큰으로 보고 삭제 대상**. `401`/`403` → 자격 증명 설정 문제이므로 토큰을 지우지 않고 행만 `failed`(값만 고치면 다음 사건부터 정상이 된다). `429`/`5xx` → `failed`. 어느 경우에도 예외를 밖으로 올리지 않는다.
- 값은 로그에 남기지 않는다(상태 코드와 FCM 오류 코드만).

## 데이터 흐름

### 흐름 1. 사건 → 원장 (트랜잭션 안)
사용자·cron 동작 → 기존 함수가 상태·점수를 확정 → 같은 트랜잭션에서 `enqueue_notification` 1행 insert → 커밋. 이 트랜잭션에는 네트워크 호출이 없다. enqueue가 실패해도 `warning` 한 줄만 남고 판정은 커밋된다.

### 흐름 2. 원장 → FCM → 기기 (트랜잭션 밖)
cron `notify-tick`(1분) → `enqueue_deadline_reminders()`(N6) → `dispatch_notifications()` → `net.http_post`(헤더 `x-notify-secret`) → Edge `send-notifications` → `claim_notifications` → 문구 조립 → FCM → `record_notification_result`. 사건 확정과 도착 사이의 지연은 최대 약 1분이고, spec의 "알림이 판정보다 나중"이라는 선택 안에 있다. 즉시 발송(사건 Edge에서 `waitUntil`로 깨우기)은 경로가 둘로 갈라지고 얻는 것이 수십 초라 만들지 않는다.

### 흐름 3. 토큰 등록
로그인 성공(세션 생김) → `MainShell`이 푸시 시작 → 권한 상태 조회 → 권한이 있으면 `getToken()` → `register_push_token` → 이후 `onTokenRefresh` 스트림에서 같은 RPC. 실패는 `debugPrint`만(토스트 없음).

### 흐름 4. 권한 요청
첫 대결 생성 성공 또는 첫 참가 성공 직후 → `getNotificationSettings()`가 `notDetermined`일 때만 `requestPermission()` → 허용이면 흐름 3으로 토큰 등록. 거부면 아무것도 하지 않는다. **"이미 물어봤다"를 앱이 따로 저장하지 않는다** — OS 상태(`denied`)가 그 기록이므로 두 곳에 상태를 두지 않는다(안드로이드 12 이하는 권한 개념이 없어 항상 허용으로 나온다).

### 흐름 5. 로그아웃·탈퇴
- 로그아웃: `AuthRepository.signOut()`이 (1) `getToken()`으로 현재 토큰을 얻어 `unregister_push_token`, (2) `FirebaseMessaging.deleteToken()`(그 설치에 새 토큰이 발급되게), (3) `auth.signOut()`. (1)·(2)의 실패는 로그아웃을 막지 않고 `debugPrint`만 남긴다.
- 탈퇴: `delete_account`가 서버에서 내 토큰 행과 내 원장 행을 지운다. 앱은 따로 할 일이 없다(사진 정리 선례와 달리 Storage가 아니라 테이블이라 RPC가 다 한다).

### 흐름 6. 알림 탭
백그라운드 탭 → `onMessageOpenedApp` / 종료 상태에서 탭 → `getInitialMessage()` → `data.battle_id` 추출(`notification_payload.dart`의 순수 함수) → `pendingBattleOpenProvider`에 기록 → `MainShell`이 이를 보고 (1) `내 대결` 탭으로 이동, (2) `fetchBattle(id)`로 **열 수 있는지 먼저 확인**, (3) 성공하면 `BattleDetailScreen`을 push, 실패하면 아무것도 하지 않고 `debugPrint`만 남긴다. 미로그인 상태면 `MainShell`이 없으므로 값은 그대로 버려지고 로그인 화면이 보인다(spec: 오류 화면을 보여 주지 않는다).

### 흐름 7. 포그라운드 수신
앱을 보고 있는 동안 도착한 메시지는 시스템 트레이에 뜨지 않고 `onMessage`로만 온다. 알림을 직접 그리지 않고(로컬 알림 패키지를 넣지 않는다) `myBattlesProvider`와 해당 `battleDetailProvider(battle_id)`를 invalidate해 화면을 갱신한다. 앱 안 확인 경로(목록 상태 줄·상세)가 이미 spec이 정한 자리이므로 이것으로 충분하다.

## 화면

새 화면은 없다. 기존 화면에 붙는 것만 있다.

| 화면 | 변경 | 상태 |
|---|---|---|
| `main_shell.dart` | `ConsumerStatefulWidget`으로 바꿔 `initState`에서 푸시 시작(토큰 등록·스트림 구독·초기 메시지), `dispose`에서 구독 해제. 프로필 탭 복귀 시 `notificationPermissionProvider`도 invalidate(기기 설정에서 켜고 돌아온 경우) | 푸시 초기화 실패는 화면에 영향 없음 |
| `battle_recruits_screen.dart` | 참가 성공 경로(VS 인트로 → 토스트 → 탭 이동) **뒤**에 권한 요청. 시스템 다이얼로그가 연출을 가리지 않게 마지막에 둔다. 대결 만들기 화면이 `pop(true)`로 성공을 알리면 같은 요청을 한다 | 요청 중/거부/허용 모두 화면 변화 없음 |
| `create_battle_screen.dart` | 등록 성공 시 `pop(true)`(현재는 `pop()`) | 기존과 동일 |
| `profile_screen.dart` + 신규 `notification_section.dart` | AI 동의 섹션 **위**에 조건부 창 한 개. 알림이 꺼져 있을 때만 보인다: "알림이 꺼져 있어요" + "기기 설정 > 앱 > 투두두두 > 알림에서 켤 수 있어요". 앱 안 on/off 스위치는 두지 않는다(결정 4) | 조회 중=표시 안 함, 켜져 있음=표시 안 함, 조회 실패=표시 안 함(`debugPrint`만). 잘못된 안내를 띄우지 않는 쪽을 택한다 |

기기 설정으로 바로 보내는 버튼은 만들지 않는다 — `url_launcher`/`app_settings` 같은 패키지가 필요해지고, 안내 문구만으로 목적이 달성된다(CLAUDE.md "새 패키지 추가 전 기존 패키지로 가능한지 확인").

### 클라이언트 패키지
| 패키지 | 이유 |
|---|---|
| `firebase_core` | Firebase 초기화. `firebase_messaging`의 전제이고 대체 수단이 없다 |
| `firebase_messaging` | FCM 토큰 발급·갱신·메시지 수신의 공식 경로. 권한 요청(`requestPermission`)까지 이 패키지가 하므로 **`permission_handler`를 넣지 않는다** |

넣지 않는 패키지: `flutter_local_notifications`(포그라운드 알림을 직접 그리지 않기로 했으므로 불필요), `permission_handler`, `url_launcher`. 새 패키지 두 개를 넣는 이유는 커밋 메시지에 적는다(CLAUDE.md).

### 안드로이드 배선
| 파일 | 변경 | 함정 |
|---|---|---|
| `android/settings.gradle.kts` | `plugins`에 `id("com.google.gms.google-services") version "<AGP 9.1.0과 호환되는 최신>" apply false` | 이 저장소는 AGP 9.1.0 / Kotlin 2.4.0이다. google-services 플러그인 버전이 맞지 않으면 빌드가 실패하므로 그때는 오너 확인 후 버전을 올린다 |
| `android/app/build.gradle.kts` | `plugins`에 `id("com.google.gms.google-services")` | `dev.flutter.flutter-gradle-plugin` **뒤**에 둔다 |
| `android/app/google-services.json` | 오너가 Firebase 콘솔에서 내려받아 둔다 | 없으면 릴리스 빌드가 깨진다. 이 파일은 클라이언트 설정이고 서버 시크릿이 아니며 저장소가 비공개이므로 **커밋한다**(없는 상태로 배포 빌드를 돌리면 원인을 찾기 어렵다) |
| `AndroidManifest.xml` | `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` 추가, `<meta-data android:name="com.google.firebase.messaging.default_notification_icon" .../>`로 흰색 실루엣 아이콘 지정 | 실루엣 아이콘을 지정하지 않으면 API 21+에서 런처 아이콘이 흰 사각형으로 보인다. 아이콘은 기존 생성기(`tool/generate_launcher_icons.dart`)에 출력 하나를 더해 만든다 |
| `minSdk` | `firebase_core`/`firebase_messaging`의 요구치가 `flutter.minSdkVersion`보다 높으면 `minSdk = 23`처럼 고정한다 | Gradle 오류 메시지로 드러난다. 값을 짐작해 미리 올리지 않는다 |

### 클라이언트 파일 (신규는 `lib/core/push/`)
화면이 없고 여러 feature(참가·생성·프로필·셸)가 함께 쓰므로 feature 폴더가 아니라 `core`에 둔다(선례: `core/supabase`, `core/navigation`).

| 파일 | 역할 |
|---|---|
| `core/push/push_messaging.dart` | `FirebaseMessaging`을 감싼 얇은 계층(권한 상태·요청, 토큰 조회, 토큰 갱신 스트림, 메시지 스트림, 초기 메시지). 위젯 테스트에서 가짜로 바꿀 수 있게 provider로 노출(선례: `evidenceCameraProvider`, `vsIntroSeenStoreProvider`) |
| `core/push/push_repository.dart` | `register_push_token`·`unregister_push_token` RPC |
| `core/push/notification_payload.dart` | `data`에서 `battle_id`를 뽑는 **순수 함수**(형식이 틀리면 null). 유닛 테스트 대상 |
| `core/push/push_service.dart` | 시작/중지, 권한 요청 시점 함수(`ensureNotificationPermissionAfterFirstBattle`), 메시지 처리(포그라운드 invalidate, 탭 → `pendingBattleOpenProvider`) |
| `core/push/push_providers.dart` | `pushMessagingProvider`, `pushRepositoryProvider`, `pushServiceProvider`, `notificationPermissionProvider`, `pendingBattleOpenProvider` |

`main.dart`는 `SupabaseEnv.isConfigured`일 때 `Firebase.initializeApp()`을 함께 부른다. 실패하면 `debugPrint`만 남기고 앱은 그대로 뜬다 — 알림은 어떤 기능의 관문도 아니다(spec).

## FCM 자격 증명과 보관 위치

| 값 | 어디에 | 이유 |
|---|---|---|
| 서비스 계정 JSON(base64 한 줄) | **Edge 함수 시크릿** `FCM_SERVICE_ACCOUNT` | 이 값을 읽는 것은 Edge뿐이다. Vault는 **Postgres가 읽어야 하는 값**(cron이 pg_net으로 쓸 URL·시크릿)만 담는 자리다. 선례 그대로: `GEMINI_API_KEY`는 함수 시크릿, `judge_function_url`은 Vault. 여러 줄 PEM이 환경변수에서 깨지는 문제를 피하려고 JSON 전체를 base64로 한 줄로 만든다 |
| cron→Edge 관문 값 | 함수 시크릿 `NOTIFY_CRON_SECRET` **와** Vault `notify_cron_secret`(같은 값) | 한쪽은 Edge가 비교하고, 다른 쪽은 Postgres가 헤더에 실어 보낸다 |
| Edge 주소 | Vault `notify_function_url` | `dispatch_notifications`가 SQL에서 읽는다 |

값은 이 문서·마이그레이션·코드·로그·커밋 어디에도 쓰지 않는다. 이름만 참조한다.

### 오너가 손수 해야 할 준비 작업 (순서대로)
1. Firebase 콘솔에서 새 프로젝트를 만든다(FCM은 무료 등급으로 충분하다).
2. 그 프로젝트에 **Android 앱**을 추가한다. 패키지 이름은 `com.todododo.todododo`. SHA-1 지문 등록은 필요 없다(이 앱의 구글 로그인은 브라우저 리디렉션 방식이다 — DEPLOY.md 1번 참고).
3. `google-services.json`을 내려받아 `android/app/google-services.json`에 둔다.
4. 프로젝트 설정 → 서비스 계정 → **새 비공개 키 생성**으로 JSON을 받는다. 이 값이 서버의 FCM 자격 증명이다(에이전트에게 전달하지 않는다).
5. 그 JSON을 base64 한 줄로 만들어 `supabase secrets set FCM_SERVICE_ACCOUNT=<값>`.
6. 긴 난수 문자열을 하나 만들어 `supabase secrets set NOTIFY_CRON_SECRET=<값>`.
7. Supabase 대시보드 Vault에 두 항목을 넣는다: `notify_function_url` = `https://<project-ref>.supabase.co/functions/v1/send-notifications`(이미 들어가 있는 `judge_function_url`과 같은 형식이다), `notify_cron_secret` = 6번과 **같은 값**.
8. `supabase functions deploy send-notifications`.
9. 첫 1분 확인: `cron.job_run_details`에서 `notify-tick`이 성공했는지, 대시보드 함수 로그에 401이 없는지(401이면 6·7의 값이 다른 것이다).
10. Play Console 데이터 보안 양식과 개인정보처리방침(별도 저장소 `todododo-legal`) 갱신 — 7단계.

값을 넣기 전에 배포해도 안전하다: Vault 값이 없으면 `dispatch_notifications`가 0을 반환하고 아무것도 보내지 않으며, 원장은 그대로 쌓여 값이 들어온 순간부터 이어서 나간다(선례: `dispatch_quality_judgments`).

## 구현 단계 분할

각 단계 끝에 `flutter analyze` 이슈 0 + `flutter test` 통과 + 해당 SQL 테스트(원격, 롤백) 통과 후 커밋한다. **스키마 변경이 있는 단계는 원격 적용 전에 오너 확인을 받는다**(로컬 Docker 없음). 세부 파일 목록·커밋 순서의 최종 확정은 plan.md 영역이다.

| 단계 | 스키마 변경 | 내용 |
|---|---|---|
| 1 | **있음(오너 확인)** | 토큰·원장 스키마와 RPC |
| 2 | 없음 | 클라이언트 Firebase 배선·권한·토큰 등록/해제·프로필 안내 |
| 3 | **있음(오너 확인)** | 사건 지점 6곳에 enqueue 배선 |
| 4 | **있음(오너 확인)** | 발송 경로(Edge·cron·Vault) — 첫 실발송 |
| 5 | 없음 | 알림 탭 라우팅·포그라운드 처리 |
| 6 | **있음(오너 확인)** | N6 마감 임박 |
| 7 | 없음 | 문서·배포 준비 |

**1단계 — 토큰·원장 스키마와 RPC (스키마 변경 있음)**
- 파일: `supabase/migrations/..._push_tokens_and_outbox.sql`(`device_push_tokens` + RLS, `notification_outbox` + RLS(정책 없음), `enqueue_notification`, `register_push_token`, `unregister_push_token`, `claim_notifications`, `record_notification_result`, `delete_account` 재정의(토큰·원장 삭제)), `supabase/tests/push_token_smoke.sql`.
- 커밋: `feat: 기기 알림 토큰과 알림 발송 원장 스키마`.
- 검증: 스모크 `ok=t`(토큰 upsert·소유자 교체·본인 삭제·탈퇴 삭제, 남의 토큰 select 0행, anon RPC 권한 오류, enqueue 중복 1행, claim 후 두 번째 claim 0행, 토큰 없는 수신자 `dropped`).
- 이 단계에서 앱 동작은 전혀 바뀌지 않는다(아무도 원장에 넣지 않는다).

**2단계 — 클라이언트 수신 배선과 권한 (스키마 변경 없음)**
- 파일: `pubspec.yaml`(패키지 2개), `android/settings.gradle.kts`·`android/app/build.gradle.kts`·`AndroidManifest.xml`·`android/app/google-services.json`(오너), `tool/generate_launcher_icons.dart`(알림용 흰색 실루엣 추가), `lib/main.dart`, `lib/core/push/*`(5개), `lib/core/navigation/main_shell.dart`, `lib/features/battle/presentation/battle_recruits_screen.dart`·`create_battle_screen.dart`, `lib/features/profile/presentation/{profile_screen.dart,notification_section.dart}`, `lib/features/auth/data/auth_repository.dart`, `lib/core/strings.dart`.
- 커밋: `feat: FCM 수신 배선과 알림 권한 요청` / `feat: 프로필 알림 꺼짐 안내`(화면이라 따로).
- 검증: `flutter test`(기존 위젯 테스트가 가짜 `pushMessagingProvider`로 통과하는 것 포함), 실기기에서 첫 참가·첫 생성 직후 권한 다이얼로그가 한 번만 뜨고 거부해도 전 기능이 동작, 허용 시 `device_push_tokens`에 행 1개(오너가 확인), 로그아웃 후 그 행이 사라짐, 두 기기 로그인 시 2행.

**3단계 — 사건 지점 enqueue (스키마 변경 있음)**
- 파일: `supabase/migrations/..._notification_events.sql`(`join_battle`·`finalize_battle`·`void_battle`·`accept_submission`(시그니처 유지)·`record_speed_verdict`·`delete_account` 재정의), `supabase/tests/notification_events_smoke.sql`.
- 커밋: `feat: 대결 사건에서 알림 원장 적재`.
- N1~N5를 한 마이그레이션에서 함께 배선한다(우선순위가 P0/P1로 갈리지만, `record_speed_verdict`·`delete_account`를 두 번 재정의하지 않으려면 한 번에 고치는 것이 맞다. 범위를 줄여야 하면 N4·N5 두 줄만 빼면 된다).
- 검증: 스모크 `ok=t` — N2가 판정·포기·마감 정산 **세 경로 모두**에서 양쪽에 1행씩, 같은 종결로 두 번 생기지 않음, 포기한 본인에게는 없음, N4가 `error`·종결 트랜잭션에서는 없음, N3가 속도전·이미 제출한 사람에게는 없음, N5의 `slot_returned` 분기, payload에 `reason`·`object_path`·`display_name` 키가 없음, enqueue가 실패해도(일부러 제약 위반을 유발) 종결·점수가 정상 커밋됨.

**4단계 — 발송 경로 (스키마 변경 있음)**
- 파일: `supabase/migrations/..._notification_dispatch.sql`(`dispatch_notifications`, cron `notify-tick` 등록), `supabase/functions/send-notifications/index.ts`, `supabase/functions/_shared/{fcm.ts,notification_text.ts}` + `*_test.ts`, `supabase/config.toml`.
- 커밋: `feat: 알림 발송 Edge Function과 발송 주기 작업`.
- 검증: `deno test`(문구 6종·프라이버시 금지 항목 부재·점수 0 문장·남은 시간 표기, FCM 요청 조립, 죽은 토큰 판별, 시크릿 불일치 401), 오너가 시크릿·Vault 값 입력 후 `functions deploy` → 두 계정으로 매칭·제출·판정을 한 번 돌려 실제 알림 6종 중 도착 가능한 것들을 확인, `notification_outbox`가 `sent`로 바뀌는지, 잘못된 토큰을 심어 두면 `device_push_tokens`에서 지워지는지.

**5단계 — 알림 탭과 포그라운드 (스키마 변경 없음)**
- 파일: `lib/core/push/{push_service.dart,notification_payload.dart,push_providers.dart}`, `lib/core/navigation/main_shell.dart`.
- 커밋: `feat: 알림 탭으로 대결 상세 열기`.
- 검증: 유닛(payload 파싱), 위젯(pending 값이 있으면 상세가 push되고 없으면 그대로), 실기기에서 백그라운드·종료 상태 탭 각각 상세로 진입, 취소된 대결의 알림을 탭했을 때 오류 화면 없이 `내 대결` 탭에 머무름, 포그라운드 수신 시 목록이 갱신됨.

**6단계 — N6 마감 임박 (스키마 변경 있음)**
- 파일: `supabase/migrations/..._deadline_reminders.sql`(`enqueue_deadline_reminders`, `notify-tick` 명령 문자열 갱신 — 같은 이름으로 `cron.schedule`을 다시 부르면 **갱신**된다), `supabase/tests/deadline_reminder_smoke.sql`.
- 커밋: `feat: 마감 임박 알림`.
- 검증: 스모크 `ok=t` — 대상 6케이스(품질전 미제출 O / 제출 X, 속도전 미통과 O / 통과 X / 5회 소진 X, 종결·`judging`·마감 경과 X), 두 번째 실행에서 0행(한 번만), 마감이 지난 `pending` 행은 `dropped`, 6시간 문턱 경계(6시간 1분 전 X / 5시간 59분 전 O).

**7단계 — 문서·배포 준비 (스키마 변경 없음)**
- 파일: `CLAUDE.md`(범위 안의 "푸시 알림(FCM)" 문구 정리, 코딩 규칙에 예외 두 줄 — 알림 문구는 서버가 만든다 / 발송 실패는 토스트 없이 서버 로그, 개발 명령어에 `supabase functions deploy send-notifications`), `DEPLOY.md`(알림 권한·데이터 보안·`google-services.json`·서비스 계정 키 확인 항목), `TODO_BACKLOG.md`(원장 정리 정책이 필요해지면 한 줄).
- 저장소 밖(오너): 개인정보처리방침에 기기 알림 토큰의 수집·이용 목적·보유 기간(로그아웃·탈퇴·미사용 시 삭제)과 Google(FCM) 처리 위탁 반영, Play Console 데이터 보안 양식에 기기 식별자(알림 토큰) 수집 추가.
- **알림 원장 보존과 방침의 정합 확인**(결정 사항 3의 조건): `notification_outbox.payload`에 대결 제목 스냅샷이 남고 행을 지우지 않으므로, 개인정보처리방침에 적는 보유 기간과 어긋나지 않는지 이 단계에서 확인한다. 어긋나면 그때 정리 정책을 정한다(탈퇴 시 내 수신 행 삭제는 이미 1단계에 들어 있다).
- 알림은 별도 앱 내 동의를 받지 않는다(spec: FCM은 배달 수단이라 Gemini와 성격이 다르다). 방침 고지 + 안드로이드 권한 요청으로 끝낸다.

## 테스트 전략

| 무엇 | 어디서 | 수단 |
|---|---|---|
| 토큰 저장·소유자 교체·로그아웃·탈퇴 삭제, RLS와 권한(anon·authenticated 회수) | DB | `supabase/tests/push_token_smoke.sql` — 원격 실행 + 마지막 `raise exception`으로 전체 롤백(기존 스모크 형식 그대로, `SMOKE RESULT ok=...`) |
| 사건별 적재·중복 방지·제외 조건·payload 금지 키·enqueue 실패가 판정을 되돌리지 않음 | DB | `supabase/tests/notification_events_smoke.sql` |
| N6 대상 선별·한 번만·경계·마감 후 폐기 | DB | `supabase/tests/deadline_reminder_smoke.sql` |
| 문구 6종과 프라이버시 제약, FCM 요청 조립, 죽은 토큰 판별, 상수 시간 비교 | Edge(순수 함수) | `deno test supabase/functions/_shared/` — FCM·Google OAuth는 **부르지 않는다**(Gemini를 부르지 않는 기존 테스트와 같은 선) |
| payload 파싱(battle_id 추출·형식 오류), 권한 상태 → 프로필 안내 표시 여부 | Dart 순수 함수 | `flutter test` 유닛 |
| 프로필 안내 유무, 참가·생성 성공 후 권한 요청 호출, 알림 탭 시 상세 push | Dart 위젯 | `flutter test`(가짜 `pushMessagingProvider`·`pushRepositoryProvider`) |
| 실제 도착·잠금화면 표시·아이콘·탭 진입 | 실기기 | 오너 수동 체크리스트(에뮬레이터는 Play 서비스 이미지여야 하고 카메라·알림 확인이 제한적이라 실기기로 본다 — DEPLOY.md 7번과 같은 이유) |

판정 규칙을 알림 쪽에서 다시 테스트하지 않는다(규칙은 ai-judge의 SQL 순수 함수 테스트가 이미 덮는다). 알림 테스트는 "확정된 사실이 올바른 수신자에게 한 번만, 담아도 되는 내용만 담겨 쌓이는가"만 본다.

## CLAUDE.md 규칙과의 관계 확인
- **유지·준수**: 판정 로직은 DB/Edge(알림은 규칙을 계산하지 않는다), 클라이언트에서 승패 계산 금지, 스키마 변경은 마이그레이션만, RLS는 테이블 만들 때 같이, 새 RPC는 `revoke ... from public, anon` + `grant ... to authenticated`, 사용자용 SECURITY DEFINER에는 로그인 가드, service·cron 전용 함수는 `authenticated`까지 회수하고 주석에 예외 이유, 참가자 검사는 `is distinct from`, 사용자 FK는 `public.profiles`, 시크릿은 이름만 참조, 새 화면 하나 = 커밋 하나, 새 패키지는 이유를 커밋 메시지에.
- **문구를 고칠 곳(7단계)**: 범위 안의 "푸시 알림(FCM)"을 이 설계 기준으로 정리.
- **명시할 예외 두 가지(7단계에 한 줄씩 추가)**: (1) 알림 문구는 `lib/core/strings.dart`가 아니라 서버(`_shared/notification_text.ts`)가 만든다 — 앱이 종료된 상태에서도 표시돼야 한다. (2) 알림 발송 실패는 토스트를 띄우지 않고 로그만 남긴다 — 사용자가 할 수 있는 일이 없고 그 시점에 앱을 보고 있지도 않다(VS 인트로 예외와 같은 성격).
- **iOS·i18n·미래 대비 없음**: APNs·iOS 권한 분기 없음, 문구는 한국어 상수, 알림 종류별 설정·채널 체계·알림함·재발송 큐·분석을 만들지 않는다.
- **도메인 규칙과 충돌 없음**: 상태 전이(`pending→active→judging→finished|draw|voided|cancelled`)와 판정·점수·한도 규칙을 한 줄도 바꾸지 않는다. 알림은 `battles`/`battle_participants`/`player_stats`를 읽지도 쓰지도 않고, 사건 함수가 이미 계산한 값을 받아 원장에만 넣는다.

## 결정 사항
2026-09-17 오너가 3건을 모두 확정했다(초안의 "결정 필요" 3건에 대한 답, 추천안 전부 채택). **미결 항목은 없다.**

1. **품질전에서 상대가 낸 사진이 "두 번째" 사진이면(= 받는 사람이 이미 제출함) N3를 보내지 않는다.**
   - 근거: N3가 막는 손해("내가 마감까지 내지 않으면 상대가 판정 없이 이기고 -3")는 받는 사람이 아직 내지 않았을 때만 존재한다. 이 경우는 곧 `judging` 진입이고, spec이 "품질전 AI 판정 시작은 알리지 않는다(할 일이 없고 몇 분 안에 N2가 뒤따른다)"고 이미 정했다.
2. **속도전 판정이 그 트랜잭션에서 대결을 종결시켰으면 N4를 생략하고 N2만 보낸다.**
   - 근거: 같은 순간에 "상대가 기준을 통과했어요"와 "졌어요 · -3점"이 잠금화면에 두 줄로 쌓인다. spec 결정 2가 속도전 알림을 1건으로 합친 근거("거의 동시에 두 줄이 쌓이면 알림 신뢰도만 떨어진다")와 같은 상황이고, N2가 결과·점수까지 담아 정보량이 더 크다.
3. **알림 원장(`notification_outbox`)의 행은 지우지 않는다.**
   - 근거: 행을 지우면 dedup_key가 사라져 "한 사건은 한 번만"이 깨진다. 하루 1대결 제한 때문에 증가량도 작다(대결당 15행 미만).
   - 조건: payload에 대결 제목 스냅샷이 남으므로 **7단계에서 개인정보처리방침의 보유 기간과 맞는지 다시 본다.** 어긋나면 그때 정리 정책을 정한다(탈퇴 시 내 수신 행 삭제는 이미 설계에 들어 있다).
