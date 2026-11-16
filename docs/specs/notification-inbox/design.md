# notification-inbox 설계

## 참고

- spec.md: `docs/specs/notification-inbox/spec.md` (오너 결정 2026-11-13 확정 6항목 포함. 이 설계의 유일한 요구사항)
- 선례·근거로 읽은 것:
  - `CLAUDE.md`(도메인 규칙, 코딩 규칙, RPC 권한 규칙, 하지 말 것)
  - `docs/specs/push-notification/design.md`(원칙 4가지, 사건·발송 지점 표, payload 키 표, 문구가 서버에 있는 이유, 흐름 6 알림 탭)
  - `supabase/migrations/20260920120000_push_tokens_and_outbox.sql`(`notification_outbox` 원형·RLS·권한), `20261103120000_notification_events.sql`(사건 지점·kind 이름 교체·payload 실제 내용), `20261106120000_remove_battle_limits.sql`(현재 유효한 `join_battle`·`void_battle`·`delete_account`)
  - `supabase/functions/_shared/notification_text.ts`(푸시 문구의 실제 문장), `supabase/tests/notification_events_smoke.sql`(스모크 테스트 틀)
  - `lib/core/navigation/main_shell.dart`, `lib/core/push/{push_providers.dart,push_service.dart,push_repository.dart}`
  - `lib/features/profile/presentation/{profile_screen.dart,battle_records_screen.dart}`, `lib/features/profile/domain/profile_providers.dart`
  - `lib/core/{strings.dart,remaining_time.dart}`, `lib/core/theme/{app_icons.dart,app_palette.dart}`, `lib/core/widgets/{app_panel.dart,app_tag.dart,status_message.dart,app_loader.dart,keep_words_text.dart}`
  - `lib/features/battle/data/battle_repository.dart`(RPC 호출 꼴), `supabase/migrations/20260916120000_ai_consent.sql`(사용자당 한 행 테이블 + 정책 선례)

## 전제 (오너가 확정한 6항목 — 이 설계는 묻지 않고 그대로 쓴다)

1. 배포 전에 넣는다. 최소 스코프. 순서는 `push-notification` 6·7단계 뒤.
2. 쌓이는 것은 **대결 사건 7종만**. 할 일 기한 알림은 넣지 않는다.
3. 배지는 **점 하나**(개수 없음).
4. 입구는 **네 탭 앱바 전부의 종 아이콘**. 아이콘·배지는 **공용 위젯 하나**이고 네 앱바가 그것을 쓴다.
5. 보여 주는 범위는 **최근 50건**.
6. 알림함 줄 문구의 출처는 design이 정한다(아래 4장). "두 자리가 같은 사건에 모순되는 말을 하지 않는다"는 spec의 요구로 남는다.

## 설계 원칙 (전체를 관통하는 4가지)

1. **알림함은 읽기 전용 거울이다.** 판정·승부·점수·상태 전이·cron·AI 호출에 한 줄도 닿지 않는다. 쓰는 것은 "마지막으로 본 시각" 하나뿐이고 그 값은 승부와 무관하다. 알림함 조회가 전부 실패해도 대결 진행은 완전히 똑같다.
2. **원장 테이블은 계속 "정책이 하나도 없는 서버 전용 테이블"로 둔다.** 읽기를 여는 자리는 테이블이 아니라 **함수 세 개**다(3장). 그래서 "클라이언트가 못 만지는 테이블"이라는 구조적 보장이 유지되고, 검증해야 할 면이 테이블 전체가 아니라 함수 세 개로 좁아진다.
3. **줄은 payload 스냅샷과 kind만으로 그린다.** 알림함은 `battles`·`profiles`·`battle_submissions`를 **한 번도 읽지 않는다.** 상대 이름·사진·판정 사유가 줄에 닿는 길이 구조적으로 없다. payload의 금지 키 규칙(판정 사유·사진 경로·상대 표시 이름)은 그대로이고, "앱 안에서만 쓸 값"을 payload에 추가하지 않는다.
4. **지금 상태의 정답은 언제나 대결 상세다.** 알림함 줄은 **과거에 일어난 사건의 기록**이므로 "지금 기준으로 계산되는 값"(남은 시간, 해야 할 일의 촉구)을 말하지 않는다. 이 선이 spec의 트레이드오프("두 자리가 어긋나면 무엇을 믿어야 하나")를 화면에서 해결하는 장치다.

---

## 0. 먼저 고쳐 둘 사실 — kind 7종의 **실제 이름**

의뢰 문서와 spec 본문이 서로 다른 이름을 쓰고 있다. **DB에 실제로 들어 있는 이름은 아래 7개다**(`20261103120000_notification_events.sql`이 2026-11-03에 `quality_submitted` → `submitted`, `speed_verdict` → `judge_turn`으로 교체했다. `notification_text.ts`도 이 이름으로 분기한다).

| kind (실제) | 뜻 | 받는 사람 | payload 키(실제) |
|---|---|---|---|
| `matched` | 내 모집에 상대가 참가(마감이 흐르기 시작) | 생성자 | `title`, `battle_type`, `deadline_at` |
| `submitted` | 상대가 사진을 냈다(두 유형 공통) | 상대 | `title`, `battle_type` |
| `judge_turn` | 판정 창이 열렸다 = 판정할 차례 | 판정할 증거가 있는 쪽 | `title`, `battle_type`, `judge_deadline_at` |
| `deadline_soon` | 마감이 다가온다(아직 완료 못 한 사람) | 해당 참가자 | `title`, `battle_type`, `deadline_at` ※ **push 6단계가 만든다** |
| `finished` | 종결과 결과 + 이번 점수 변화 | 양쪽(포기한 본인 제외) | `title`, `battle_type`, `outcome`, `score_delta` |
| `voided` | AI 재판정이 끝내 실패해 무효 | 양쪽 | `title`, `battle_type` |
| `cancelled` | 상대 탈퇴로 내 대결이 취소됐다 | 남은 사람 | `title` |

- `outcome` 값: `win` / `completed_loss` / `loss` / `forfeit` / `draw`. 이 중 `forfeit`은 **실제로는 오지 않는다** — 포기한 본인에게는 적재하지 않기 때문이다(`finalize_battle`의 `forfeited_by is distinct from` 가드). 매핑에는 방어적으로 둔다.
- `deadline_soon`은 **아직 적재 지점이 없다**(push 6단계). 알림함 순서가 그 뒤이므로 구현 시점에는 존재한다. 혹시 6단계가 미뤄지면 그 kind의 줄이 영원히 안 보일 뿐이고 다른 동작은 영향이 없다.
- `payload`에 `title`이 없거나 빈 문자열일 수 있다고 가정한다(서버 문구가 `'「대결」'`로 대체하는 것과 같은 방어). 앱도 같은 대체값을 쓴다(4장).

---

## 1. 데이터 모델

### 1.1 `notification_outbox` — 컬럼 변경 없음, 인덱스 하나 추가

알림함을 위해 **새로 기록할 것이 없다.** 컬럼·제약·RLS(정책 없음) 전부 그대로다. 추가하는 것은 인덱스 하나뿐이다.

```sql
-- 알림함과 배지가 보는 축. 기존 인덱스는 (created_at) where status='pending'(발송기용)이라
-- 수신자별 최신 조회에 쓸 수 없고, unique (recipient_id, dedup_key)는 정렬에 쓸 수 없다.
create index notification_outbox_recipient_idx
  on public.notification_outbox (recipient_id, created_at desc, id desc);
```

- `id desc`를 함께 두는 이유: `created_at`의 기본값은 `now()`(= **트랜잭션 시작 시각**)라 같은 트랜잭션에서 한 수신자에게 두 행이 생기면 값이 같다. 정렬이 흔들리지 않게 깨뜨릴 축을 하나 더 둔다.
- 원장 행은 여전히 **지우지 않는다**(dedup 보장이 거기 걸려 있다 — push design 결정 3). 알림함은 보여 주는 범위만 자른다.
- `battle_id`가 `references public.battles (id) on delete cascade`이므로 대결 행이 사라지면 알림 행도 함께 사라진다 → "눌렀는데 가리키는 대결이 아예 없다"는 상태가 구조적으로 드물다(spec 그대로).

### 1.2 `notification_reads` — 읽음 상태(계정당 시각 하나), **신규 테이블**

```sql
create table public.notification_reads (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  seen_at timestamptz not null default now()
);

comment on table public.notification_reads is
  '알림함을 마지막으로 본 시각(계정당 한 행). 쓰기는 mark_notifications_seen만. 행별 읽음 상태는 두지 않는다.';
comment on column public.notification_reads.seen_at is
  '서버 시각으로만 찍는다(클라이언트가 값을 보내지 않는다). 이 시각보다 나중에 생긴 원장 행이 "새 알림"이다.';

alter table public.notification_reads enable row level security;
-- 정책 없음: 아래 세 함수(security definer)만 이 테이블을 만진다. 화면이 날짜 값 자체를 쓸 일이
-- 없어(목록 RPC가 함께 돌려준다) 직접 select를 열 이유가 없다(선례: quality_judgments, notification_outbox).
```

**`profiles`에 컬럼을 더하지 않은 이유**(이것이 이 선택의 핵심 근거다):

| 후보 | 채택 | 이유 |
|---|---|---|
| `profiles.notifications_seen_at` 컬럼 | ✗ | `profiles`에는 **"누구나 조회" select 정책**(`using (true)`)이 걸려 있다. 컬럼을 더하면 "이 사람이 마지막으로 앱을 열어 알림을 확인한 시각"이 로그인한 **모든 사용자에게 공개**된다. 게다가 `profiles`에는 본인 행 **update 정책**이 있어 클라이언트가 그 값을 직접 쓸 수 있다 — 미래 시각을 넣으면 배지가 영구히 꺼지고, 과거로 되돌리면 영구히 켜진다. 서버가 시각의 주인이어야 한다는 CLAUDE.md("승부 기준 시각은 언제나 서버 시각", "한도 판단은 서버가 한다")와 성격이 같은 자리다 |
| `player_stats`에 컬럼 추가 | ✗ | 그 테이블의 뜻이 "점수와 승/패/무"이고 **쓰기는 `finalize_battle`만**이라는 규칙이 있다. 알림 읽음이 끼면 두 규칙이 섞인다 |
| 기기 로컬 저장(SharedPreferences 등) | ✗ | spec "값은 기기가 아니라 계정에 붙는다"(두 기기에서 같은 배지를 두 번 지우지 않는다)를 만족하지 못한다 |
| **신규 테이블 `notification_reads`** | **✓** | 사용자당 한 행 + 정책으로 가리기 + 쓰기는 RPC만. `ai_consents`·`player_stats`·`daily_battle_slots`와 **같은 꼴의 선례**다. 공개 범위가 처음부터 0이고, 값을 찍는 주인이 서버 한 곳이다 |

- 사용자 FK는 `public.profiles`다(CLAUDE.md). 다만 탈퇴는 profiles 행을 **묘비로 남기므로 cascade가 돌지 않는다** → `delete_account`에서 명시적으로 지운다(1.3).
- `seen_at`이 없는 사용자(= 한 번도 알림함을 열지 않은 사용자)는 **행이 없는 것**으로 표현한다. 별도 플래그를 두지 않는다. 비교는 `coalesce(seen_at, '-infinity')`.

### 1.3 기존 테이블·함수 변경

| 대상 | 변경 |
|---|---|
| `notification_outbox` | 인덱스 하나 추가(1.1). 컬럼·제약·정책 변경 없음 |
| `battles`, `battle_participants`, `profiles`, `player_stats` | **변경 없음** |
| 사건 적재 함수 6곳(`join_battle`·`finalize_battle`·`void_battle`·`accept_submission`·`open_judging_window`·`delete_account`) | **적재 로직 변경 없음.** 알림함은 쌓는 쪽을 건드리지 않는다 |
| `delete_account` | 7번 단계(알림 토큰·내 수신 원장 삭제) 옆에 `delete from public.notification_reads where user_id = v_user_id;` 한 줄 추가. **가장 늦은 정의는 `20261106120000_remove_battle_limits.sql:302`이므로 그것을 그대로 복사한 뒤 한 줄만 끼워 넣는다**(선례: 매 feature가 같은 방식으로 재정의했다). 인자 없는 시그니처 유지, `create or replace`라 GRANT는 그대로 남는다 |
| cron | **신규 작업 없음.** 알림함에는 주기 작업이 없다 |

---

## 2. 읽기를 어떻게 여는가 — 테이블 정책 / 뷰 / RPC

| 후보 | 채택 | 판단 |
|---|---|---|
| A. `notification_outbox`에 `for select using (recipient_id = auth.uid())` 정책 | ✗ | RLS는 **행 단위**라서 컬럼을 가릴 수 없다. 그 순간 `status`·`attempts`·`last_error`·`lease_until`·`dedup_key`가 클라이언트 API로 함께 열린다. `last_error`는 **FCM이 준 서버 오류 문자열**이고 spec은 "내부 코드·서버 오류 메시지가 노출되지 않는다"를 수용 기준으로 적었다. 또 "최근 50건"이 클라이언트가 고르는 값이 되어 서버가 범위를 보장하지 못한다 |
| B. 뷰(`notification_inbox_v`)로 컬럼만 좁히기 | ✗ | `security_invoker = on` 뷰는 **기반 테이블의 정책을 그대로 적용**하므로 A의 정책이 먼저 있어야 한다(= A의 문제가 남는다). `security_invoker = off`(기본)로 두면 소유자 권한으로 RLS를 우회하는데, 그러면 "뷰에 걸린 grant"가 유일한 관문이 되어 함수보다 읽기 어려운 보안 경계가 된다. 어느 쪽도 함수보다 낫지 않다 |
| **C. `security definer` RPC 세 개로 감싼다** | **✓** | (1) 원장 테이블이 **정책 없는 서버 전용**이라는 구조적 보장이 **그대로 남는다** — 읽기·쓰기 어느 쪽도 테이블에 열리지 않는다. (2) 돌려주는 **컬럼을 화이트리스트로 고정**할 수 있어 `status`·`last_error`가 애초에 앱에 가지 않는다(spec "발송 상태를 사용자에게 보여 주지 않는다"를 UI 규율이 아니라 **API 경계**로 지킨다). (3) 50건 상한과 정렬이 서버 상수가 된다. (4) 선례가 이 저장소 안에 있다 — `get_player_card`·`list_open_recruits`가 정확히 같은 이유로 definer 함수다("공개 범위는 아래 where로 좁힌다") |

**그래서 `notification_outbox`의 "정책 없음"은 유지되고, 마이그레이션 주석만 사실에 맞게 고친다**(9장). 쓰기는 어떤 경로로도 열리지 않는다 — insert/update/delete 정책이 없고 함수 세 개 중 원장에 쓰는 것은 하나도 없다(spec "쓰기는 열지 않는다"가 구조적으로 성립).

**`dropped`·`failed` 행도 그대로 돌려준다.** 발송 상태로 거르지 않는 것이 이 기능의 핵심이다(알림 권한을 거부한 사용자의 행은 전부 `dropped`다). 함수가 `status`를 **읽지도 않고 돌려주지도 않는다** — 걸러내지 않겠다는 결정을 "조건문을 두지 않는 것"으로 표현한다.

---

## 3. API 계약

### 공통 규칙 (CLAUDE.md 그대로)

- 세 함수 모두 앱이 부르는 RPC다 → `security definer set search_path = public`, **첫 줄 `if auth.uid() is null then raise exception '로그인이 필요합니다.'`**, `revoke execute ... from public, anon` + `grant execute ... to authenticated`.
- 새 오류 코드·`hint`를 만들지 않는다. 실패는 전부 예외 문구 하나다.
- 참가자 검사류 비교가 없으므로 `is distinct from` 주의 사항은 해당 없음(필터는 `recipient_id = auth.uid()` 단일 등식이고, `auth.uid()`가 null이면 첫 줄 가드에서 이미 멈춘다).

### 3.1 `list_notifications()` → `jsonb`

```sql
-- 알림함 화면이 여는 유일한 조회. 상한 50은 서버 상수다(인자를 두지 않는다 - 클라이언트가
-- 범위를 늘릴 수 있으면 "최근 50건"이 서버의 보장이 아니게 된다).
-- 돌려주는 키는 화이트리스트다: status·attempts·last_error·lease_until·dedup_key는 담지 않는다
-- (발송 상태는 사용자가 할 수 있는 일이 없고, last_error는 서버 오류 문자열이다).
create function public.list_notifications()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_seen timestamptz;
  v_items jsonb;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select seen_at into v_seen from public.notification_reads where user_id = v_user;

  select coalesce(jsonb_agg(row), '[]'::jsonb) into v_items
  from (
    select jsonb_build_object(
             'id', o.id,
             'kind', o.kind,
             'battle_id', o.battle_id,
             'payload', o.payload,
             'created_at', o.created_at
           ) as row
    from public.notification_outbox o
    where o.recipient_id = v_user
    order by o.created_at desc, o.id desc
    limit 50
  ) picked;

  -- seen_at을 목록과 **같은 호출에서** 돌려준다. 두 번 나눠 물으면 그 사이에 찍히는 값 때문에
  -- "새 알림" 표시가 어긋날 수 있고, 화면은 이 스냅샷 하나로 새/읽음을 가른다(5.2).
  return jsonb_build_object('seen_at', v_seen, 'items', v_items);
end;
$$;
```

- 반환: `{"seen_at": "2026-11-13T...Z" | null, "items": [{id, kind, battle_id, payload, created_at}, ...]}` (items는 최신순).
- 발송 상태로 거르지 않는다. 대결 상태로도 거르지 않는다(끝난·무효·취소된 대결의 알림도 보인다 — spec).
- 다른 사용자의 행은 `where o.recipient_id = v_user` 하나로 막힌다. 이 함수에 "다른 사용자를 지정하는 인자"가 없다는 것이 두 번째 방어다.

### 3.2 `has_new_notifications()` → `boolean`

```sql
-- 배지 판정. 네 탭의 종 아이콘이 보는 값은 이 함수의 결과 하나다(개수를 세지 않는다 - 점 하나).
-- 비교를 서버에서 하는 이유: 클라이언트 시계를 신뢰하지 않는다(CLAUDE.md). 앱은 시각을 주지도,
-- 받지도 않고 참/거짓만 받는다.
create function public.has_new_notifications()
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  return exists (
    select 1
    from public.notification_outbox o
    where o.recipient_id = v_user
      and o.created_at > coalesce(
        (select r.seen_at from public.notification_reads r where r.user_id = v_user),
        '-infinity'::timestamptz
      )
  );
end;
$$;
```

- 행이 하나도 없는 신규 가입자는 `false`다(spec "알림을 처음 받기 전에는 새 알림 표시가 없다").
- `exists`라 `notification_outbox_recipient_idx`의 첫 두 축만으로 끝난다. 탭을 오갈 때마다 불러도 되는 무게다.

### 3.3 `mark_notifications_seen()` → `void`

```sql
-- 알림함을 열었다. 시각은 서버가 찍는다(인자 없음).
create function public.mark_notifications_seen()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  insert into public.notification_reads (user_id, seen_at)
  values (v_user, now())
  on conflict (user_id) do update set seen_at = now();
end;
$$;
```

- 멱등이다(같은 호출을 두 번 해도 행이 늘지 않는다). "전체 읽음 처리" 버튼은 만들지 않는다 — 여는 것이 곧 읽음이다(spec).

### 3.4 권한

```sql
revoke execute on function public.list_notifications() from public, anon;
grant execute on function public.list_notifications() to authenticated;
revoke execute on function public.has_new_notifications() from public, anon;
grant execute on function public.has_new_notifications() to authenticated;
revoke execute on function public.mark_notifications_seen() from public, anon;
grant execute on function public.mark_notifications_seen() to authenticated;
```

Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 주므로 `revoke`를 함께 쓴다(CLAUDE.md).

---

## 4. 문구 — 어디서 만드는가 (결정 6에 대한 답)

### 결론: **알림함 줄 문구는 앱이 만든다.** 출처는 `lib/core/strings.dart` + 순수 매핑 함수 하나.

근거 셋:

1. **서버에 문구를 둔 예외의 이유가 알림함에는 해당하지 않는다.** `notification_text.ts`가 서버에 있는 까닭은 "앱이 종료돼 있어도 **안드로이드 시스템이 앱 코드 없이** 잠금화면에 그려야 한다"였다(push design). 알림함 줄은 앱이 떠 있을 때 앱이 그린다 → 예외를 적용할 근거가 없고, CLAUDE.md의 기본 규칙("사용자에게 보이는 문자열은 `strings.dart`")이 그대로 적용된다.
2. **어디서 만들든 문구는 두 벌이다** — 재사용이 애초에 불가능하다. 푸시 문구는 **발송 시각 기준으로 남은 시간을 계산해 넣는다**(`remainingAmount`). 그 문장("마감까지 3시간 남았어요")을 과거 기록인 알림함에 그대로 두면 **틀린 말**이 된다(그 마감은 이미 지났을 수 있다). 즉 글자를 공유할 수 없다. 그렇다면 각 문구를 **쓰이는 자리의 규칙대로** 두는 쪽이 규칙을 하나 더 만들지 않는다.
3. **고치는 비용.** SQL/Edge에 앱 문구를 두면 문구 한 글자를 고칠 때 마이그레이션 또는 함수 배포가 필요하다. 알림함 줄은 앱 화면 문구이므로 앱 릴리스와 함께 움직이는 것이 맞다.

### "두 자리가 모순되지 않는다"를 지키는 방법 (spec의 요구)

구조로 세 겹을 둔다.

1. **같은 kind·같은 payload 키만 읽는다.** 두 매핑 모두 "아는 키만 읽는" 꼴이다(`notification_text.ts`의 선례 그대로). payload에 없는 것(상대 이름·사유·사진)은 양쪽 모두 말할 수 없다.
2. **알림함 줄이 말하는 사실은 같은 kind의 푸시 문구가 말하는 사실의 부분집합이다.** 알림함은 푸시보다 **더 말하지 않는다**. 특히 **지금 기준으로 계산되는 수치(남은 시간)와 촉구 문장은 말하지 않는다** — 원칙 4의 적용이고, 두 자리가 어긋날 수 있는 유일한 종류(시간에 따라 사실이 바뀌는 문장)를 아예 쓰지 않음으로써 모순을 **구조적으로** 없앤다.
3. **시제로 역할을 가른다.** 푸시는 "지금 일어난 일"을 알리고(현재형), 알림함은 "그때 일어난 일"을 적는다(과거형). 같은 사실을 다른 시제로 말하는 것은 모순이 아니고, 사용자가 "여기는 기록이고 현재 상태는 상세에 있다"를 배우는 단서가 된다.
4. **매핑 표를 design이 고정하고, 유닛 테스트가 7종 전부를 덮는다**(10장). kind를 늘릴 일이 생기면 두 표를 함께 고치는 것이 규칙이다(CLAUDE.md 코딩 규칙에 한 줄 적는다 — 9장).

### 매핑 표 (알림함 줄 ↔ 푸시 문구)

줄은 **사건 문구(주)** + **대결 제목(부)** + **시각**으로 이뤄진다(5.2). 제목은 `payload.title`을 그대로 쓰고 없으면 `대결`로 대체한다.

| kind | 알림함 사건 문구 | 아이콘 | 같은 사건의 푸시 제목(비교용) | 알림함이 **일부러 빼는** 것 |
|---|---|---|---|---|
| `matched` | 상대가 참가했어요 | `AppIcons.battle` | 대결이 시작됐어요 | "마감까지 N시간 남았어요"(지금 기준 수치) |
| `submitted` | 상대가 사진을 냈어요 | `AppIcons.camera` | 상대가 사진을 냈어요 | "아직 내 사진을 내지 않았어요" / "이제 바꿀 수 없어요"(지금 상태 단언) |
| `judge_turn` | 판정할 차례가 됐어요 | `AppIcons.judge`(신규) | 판정할 차례예요 | "N 안에 판정하지 않으면 자동 승인돼요"(지금 기준 수치·촉구) |
| `deadline_soon` | 마감이 다가왔어요 | `AppIcons.clock` | 마감이 다가와요 | "마감까지 N시간 남았어요" |
| `finished` (`win`) | 이겼어요 · {+3점} | `AppIcons.trophy` | 이겼어요! | — |
| `finished` (`draw`) | 무승부예요 · {-1점} | `AppIcons.hourglass` | 무승부예요 | — |
| `finished` (`completed_loss`·`loss`·`forfeit`) | 졌어요 · {-1점} | `AppIcons.lose` | 졌어요 | "기준을 통과해서 감점이 줄었어요"(감면 설명은 상세가 한다) |
| `voided` | 판정이 무효가 됐어요 | `AppIcons.warning` | 판정이 무효가 됐어요 | "점수와 전적에 반영되지 않아요"(상세의 무효 배너가 이미 말한다) |
| `cancelled` | 상대가 탈퇴해서 취소됐어요 | `AppIcons.close` | 대결이 취소됐어요 | — |

- 점수 조각: `score_delta != 0`이면 기존 `AppStrings.battleScoreDelta(delta)`를 그대로 쓴다(`+3점` / `-1점`). **`0`이면 `점수 변화 없음`**(새 문구). 0은 하한에 걸린 경우라 `0점`이라고 적으면 사실과 어긋난다 — 서버 문구가 같은 이유로 문장을 바꾸는 것과 같은 처리다. 하한 설명("점수는 0점 아래로 내려가지 않아요")은 줄에 붙이지 않는다(상세가 말한다).
- **모르는 kind는 줄을 그리지 않는다**(매핑이 null → 그 항목을 건너뛴다). `notification_text.ts`의 `default: return null`과 같은 태도 — 뜻을 모르는 채로 글자를 띄우지 않는다. 체크 제약이 7종을 보장하므로 실제로는 오지 않는다.
- **상대의 표시 이름을 쓰지 않는다.** 푸시와 같이 "상대"로만 부른다(payload에 이름이 없고, 이름을 채우려면 알림함이 대결·프로필을 추가로 읽어야 해서 원칙 3이 깨진다).

### 시각 표기

- **한 가지 꼴만 쓴다: `11월 8일 오후 3:04`.** 오늘 것도 같은 꼴이다.
- 상대 표기("3분 전")를 쓰지 않는 이유: 시간이 흐르는 것만으로 글자가 바뀌어 `TimeTicker`를 끌어와야 하고, 과거 사건에 "지금으로부터"를 말할 이유가 약하다.
- `todo-due-date`의 `남음`/`지남` 표와 **섞지 않는다**(spec). 그 표는 **기한**을 말하는 표이고, 알림함은 사건이 **언제 일어났는지**를 말한다. `formatRemaining`·`formatDueLabel`을 쓰지 않는다.
- 연도는 적지 않는다. 50건 범위에서 1년을 넘는 줄은 사실상 없고, 넘더라도 그 줄의 뜻은 "오래된 것"이면 충분하다.

### `strings.dart`에 더하는 문구 (전부 신규, 한국어)

```
notificationInboxTitle        = '알림'                  // 앱바 제목 + 종 버튼 tooltip
notificationNewSemantics      = '새 알림 있음'          // 배지의 화면 읽기 라벨
notificationInboxEmpty        = '아직 받은 알림이 없어요.'   // 재촉하지 않는다(spec)
notificationInboxLoadFailed   = '알림을 불러오지 못했어요.'
notificationBattleGone        = '더 볼 수 없는 대결이에요.'   // 열 수 없는 대결을 눌렀을 때의 토스트
notificationFallbackTitle     = '대결'                  // payload.title이 없을 때
notificationScoreUnchanged    = '점수 변화 없음'
notificationMatched           = '상대가 참가했어요'
notificationSubmitted         = '상대가 사진을 냈어요'
notificationJudgeTurn         = '판정할 차례가 됐어요'
notificationDeadlineSoon      = '마감이 다가왔어요'
notificationFinishedWin       = '이겼어요'
notificationFinishedLoss      = '졌어요'
notificationFinishedDraw      = '무승부예요'
notificationVoided            = '판정이 무효가 됐어요'
notificationCancelled         = '상대가 탈퇴해서 취소됐어요'
notificationTime({required int month, required int day, required bool isAm,
                  required int hour12, required int minute})  // '11월 8일 오후 3:04'
```

`strings.dart`의 알림 절에 있는 주석("알림 **본문** 문구는 여기 없다 — 서버가 만든다")은 **"푸시 본문은 서버, 앱 안 알림함 줄은 여기"로 고친다**(9장).

---

## 5. 화면

새 화면 하나(`알림`)와, 기존 네 앱바에 붙는 공용 버튼 하나다. **탭은 늘지 않고**, 내 대결 목록의 구역·스크롤 구조는 손대지 않는다(알림함은 push한 새 화면이다 — spec).

### 5.1 공용 종 아이콘 — `NotificationBell`

오너가 "네 탭 앱바 전부"를 골랐으므로 **같은 것을 네 벌 관리하지 않기 위해 위젯을 하나로 둔다.** 네 화면은 `actions: const [NotificationBell()]` 한 줄씩만 더한다.

```
AppBar(
  title: ...,
  actions: const [NotificationBell()],   // 내 대결 / 대결 찾기 / 할 일 / 프로필 네 곳 모두 같은 줄
)
```

| 항목 | 정함 |
|---|---|
| 모양 | `IconButton` + `Icon(AppIcons.bell, size: 24)`. 앱바 기본 아이콘 색을 따른다(아이콘 한 벌 규칙) |
| 배지 | Material `Badge(smallSize: 8, isLabelVisible: hasNew, backgroundColor: AppPalette.primary, child: Icon(...))`. **라벨 없음 = 점 하나**(확정 3). 숫자 배지를 만들지 않는다 |
| 색 | `primary`. `danger`를 쓰지 않는 이유: 이 앱의 danger는 포기·삭제처럼 **되돌릴 수 없는 동작**의 색이다. 새 알림은 위험이 아니다. 배지와 목록의 "새 알림 점"이 **같은 색·같은 크기**여서 같은 뜻으로 읽힌다(5.2) |
| 값 | `ref.watch(hasNewNotificationsProvider)`. **네 앱바가 같은 provider 하나를 본다** → 값이 어긋날 수 없다 |
| 로딩·실패 | 점을 **그리지 않는다**(`hasNew = false`). 실패는 `debugPrint`만. 근거: 잘못된 안내를 띄우지 않는 쪽을 택한 선례(프로필의 "알림이 꺼져 있어요"가 조회 실패 시 표시하지 않는 것)와 같고, 사용자가 할 수 있는 일이 없다 |
| 누르면 | `Navigator.push(MaterialPageRoute(builder: (_) => const NotificationInboxScreen()))` |
| 접근성 | `tooltip: AppStrings.notificationInboxTitle`. `hasNew`일 때 `Semantics(label: AppStrings.notificationNewSemantics)`로 감싼다(점은 색만으로 전달되면 안 된다) |

**할 일 탭·프로필 탭에 대결 배지가 뜨는 어긋남**(spec이 (B)안의 대가로 적은 것)은 이렇게 받아들인다: 종 아이콘은 **탭의 내용과 무관한 "앱 전체의 알림함 입구"**이고 그 입구는 네 탭에서 같은 자리(앱바 오른쪽 끝)·같은 모양이다. 탭마다 다르게 보이거나 어떤 탭에서는 숨는 쪽이 오히려 "이 배지가 무엇에 대한 것인지"를 흔든다. 프로필 메뉴에는 알림함 입구를 **두지 않는다**(spec: 입구는 한 종류). 2026-11-12에 정리된 프로필 메뉴 세 줄은 그대로다.

### 5.2 알림함 화면 — `NotificationInboxScreen`

`BattleRecordsScreen`과 같은 결의 **push된 목록 화면**이다(앱바 + `ListView.separated` + `AppPanel.raised` 카드 + 가장자리 20 / 항목 사이 12).

```
Scaffold(
  appBar: AppBar(title: KeepWordsText(AppStrings.notificationInboxTitle)),   // 종 아이콘 없음
  body: <상태별>
)
```

| 상태 | 화면 |
|---|---|
| 로딩 | `Center(child: AppLoader.medium())` — 지난 대결 화면과 같다 |
| 빈 상태 | `StatusMessage.empty(icon: AppIcons.bellOutlined, message: AppStrings.notificationInboxEmpty, fill: true)`. 대결을 재촉하는 문구·버튼을 두지 않는다(spec) |
| 실패 | `StatusMessage.error(message: AppStrings.notificationInboxLoadFailed, action: 다시 시도 버튼, fill: true)` + `debugPrint`. 토스트는 띄우지 않는다(화면이 이미 사실을 말하고 있고 `다시 시도`로 할 일을 준다 — 목록 조회 실패의 기존 처리와 같은 선) |
| 목록 | `ListView.separated(padding: EdgeInsets.fromLTRB(20, 16, 20, 24), separatorBuilder: SizedBox(height: 12))` |

**한 줄(카드 하나)의 구성** — `AppPanel.raised(onTap: ...)`:

```
[새 알림 점 8 | 읽은 알림은 같은 크기의 빈 자리]  8
[사건 아이콘 20, onSurfaceVariant]               12
[Expanded Column
   사건 문구     bodyLarge · w700            // 4장 매핑 표
   (4)
   대결 제목     bodyMedium · onSurfaceVariant · ellipsis 1줄 ]
                                                 12
[시각          bodySmall · onSurfaceVariant]      // '11월 8일 오후 3:04', 위쪽 정렬
```

- **새 알림과 읽은 알림의 구분은 왼쪽 점 하나뿐이다.** 글자 굵기·배경색을 바꾸지 않는다. 근거: 배지와 **같은 기호(8dp primary 점)**를 쓰면 "앱바의 그 점이 이 줄들 때문이었다"가 설명 없이 이어진다. 읽은 줄에도 **같은 크기의 빈 자리**를 남겨 글자 왼쪽 선이 흔들리지 않게 한다.
- "새 알림"의 기준은 **화면을 처음 열었을 때 받은 `seen_at` 스냅샷**이다. 이 값을 화면 state에 한 번 붙잡아 두고(`_seenAtAtOpen`), 그 뒤 목록이 다시 읽혀도 **기준을 바꾸지 않는다.** 그래서 알림함을 보고 있는 동안 표시가 눈앞에서 사라지지 않는다. 판정은 `created_at.isAfter(_seenAtAtOpen)`이고, 스냅샷이 null(처음 여는 사용자)이면 전부 새 알림이다.
- 카드를 누르는 것 말고 **어떤 동작도 없다**(삭제·스와이프·메뉴·판정·제출 없음 — spec 범위 밖).
- **당겨서 새로고침은 두지 않는다**(P1). 근거: 가장 가까운 선례(지난 대결 화면)에 없고, provider가 `autoDispose`라 화면을 닫고 다시 열면 새로 읽는다. 알림함을 열어 둔 채 푸시를 받은 경우는 포그라운드 처리가 목록을 다시 읽어 준다(6장 흐름 5)—"머물러 있는데 갱신되지 않는다"는 구멍이 그 자리에서 막힌다.

### 5.3 누르면 어디로 가는가

**그 사건이 일어난 대결 상세**다. 푸시를 탭했을 때와 같은 곳·같은 관문을 쓴다.

```
줄 탭
 → battleRepository.fetchBattle(item.battleId)      // "열 수 있는가"를 먼저 서버에 묻는다
 → 성공: Navigator.push(BattleDetailScreen(battleId: ...))   // 알림함은 아래에 남는다
 → 실패: debugPrint + 토스트(AppStrings.notificationBattleGone)로 알리고 알림함에 머문다
```

- **푸시 경로와 공유하는 것**: 도착지(`BattleDetailScreen`)와 **선확인 관문**(`fetchBattle`을 먼저 불러 열 수 있는지 본다). 오류 화면을 띄우지 않는 태도도 같다.
- **다른 것 하나**: 푸시 경로(`MainShell._openPendingBattle`)는 실패 시 **조용히** 넘어가지만(알림을 탭한 순간 사용자가 앱 안에 있다고 보장할 수 없고 토스트를 띄울 맥락이 없다), 알림함은 **토스트 한 줄을 띄운다**(spec: 아무 반응이 없으면 앱이 고장 난 것으로 읽힌다). 처리가 갈리므로 두 코드를 억지로 한 함수로 합치지 않는다 — 공유하는 것은 관문의 **규칙**이다.
- 끝난·무효·취소된 대결의 상세는 지난 대결 목록에서 열리는 것과 같은 화면이라 그대로 열린다.
- 상세에서 뒤로 나오면 알림함이 그대로 있다(`autoDispose` provider는 화면이 살아 있어 유지된다 — 목록을 다시 읽지 않는다).

---

## 6. 데이터 흐름

### 흐름 1. 배지 — 네 탭이 같은 값 하나를 본다

```
NotificationBell(4개) → ref.watch(hasNewNotificationsProvider)
  → NotificationRepository.hasNew() → RPC has_new_notifications() → bool
  → true면 점
```

`hasNewNotificationsProvider`는 `FutureProvider.autoDispose<bool>`이다.
- `autoDispose`인데도 탭을 오가며 버려지지 않는 이유: 네 탭은 `IndexedStack`에 **동시에 살아 있어** 구독이 끊기지 않는다. 그리고 로그아웃으로 `MainShell`이 사라지면 **값이 버려진다** — 다음 사용자가 이전 사용자의 배지를 보는 일이 없다(`todosProvider`가 autoDispose가 아니어서 생긴 알려진 문제의 반대 선택이다).

### 흐름 2. 배지를 **언제 다시 읽는가**

| 계기 | 어디서 | 왜 |
|---|---|---|
| 셸이 처음 뜰 때(로그인 직후) | provider 첫 watch | 자리를 비운 동안 쌓인 것을 앱을 열자마자 알린다 |
| **탭 전환**(네 방향 모두) | `MainShell`의 기존 `ref.listen(selectedTabProvider)`에 `ref.invalidate(hasNewNotificationsProvider)` 한 줄 추가 | 사용자가 앱 안에서 움직이는 가장 흔한 계기. `exists` 한 번이라 가볍다. 기존 탭별 invalidate 블록과 달리 **탭을 가리지 않는다**(배지는 탭에 속한 값이 아니다) |
| **앱 재개**(백그라운드 → 포그라운드) | `MainShell`에 `AppLifecycleListener(onResume: ...)`를 두고 invalidate(선례: `lib/core/widgets/time_ticker.dart`가 같은 API를 쓴다) | 탭을 바꾸지 않고 돌아오는 경로가 가장 흔한 누락 구멍이다 |
| **포그라운드 푸시 수신** | `PushService._handleForegroundMessage`에 `invalidate(hasNewNotificationsProvider)`(+ 알림함이 열려 있으면 함께 갱신되도록 `invalidate(notificationInboxProvider)`) 추가 | 앱을 보고 있는 동안 도착한 사건이 배지에 그 자리에서 반영된다(spec P1이 "좋지만 필수는 아니다"라고 한 것을 한 줄로 얻는다) |
| **알림함을 열어 읽음을 찍은 직후** | 알림함 화면 | 점이 사라지는 순간이다(흐름 3) |

주기 폴링을 두지 않는다(배터리·요청 수를 늘리고, 앱을 열지 않는 사용자의 손해를 막는 것은 여전히 푸시뿐이다 — spec).

### 흐름 3. 알림함 열기 → 읽음 찍기

```
종 탭 → NotificationInboxScreen
  → ref.watch(notificationInboxProvider)  (FutureProvider.autoDispose<NotificationInbox>)
      → RPC list_notifications() → {seen_at, items}
  → 첫 성공 로드에서 seen_at을 화면 state에 붙잡는다(_seenAtAtOpen, 한 번만)
  → 같은 자리에서 RPC mark_notifications_seen() 1회
      → 성공: ref.invalidate(hasNewNotificationsProvider)  // 점이 사라진다
      → 실패: debugPrint만
```

- **찍는 시점을 "첫 성공 로드 직후"로 둔 이유**: 조회가 실패했으면 사용자는 아무것도 보지 못했다. 그 상태에서 읽음을 찍으면 **보지 못한 알림이 읽은 것이 된다.** 화면 진입만으로 찍지 않는다.
- **한 번만 찍는다.** 당겨서 새로고침도 없고, 목록이 다시 읽혀도 다시 찍지 않는다. 그래서 알림함을 보고 있는 동안 도착한 알림은 **다음에 다시 새 알림으로 보인다**(그 줄은 `_seenAtAtOpen`보다 나중이라 점이 붙고, 닫고 나가면 배지도 다시 켜진다). 조금 어색하지만 **"보여 준 적 없는 것을 읽음으로 만들지 않는다"**가 더 중요하다.
- **읽음 찍기 실패를 토스트로 알리지 않는다.** 근거: 사용자가 할 수 있는 일이 없고(다시 누를 버튼이 없다), 다음에 알림함을 열면 저절로 맞는다. 실패해도 목록은 이미 보이고 있어 기능이 막히지 않는다. 이것은 CLAUDE.md "에러는 삼키지 않는다"의 **새 예외**이므로 그 목록에 한 줄 적는다(9장) — 홈 위젯 캐시 발행·기한 알림 예약 실패와 같은 성격이다.
- **계정당 한 값이라 기기를 두 대 써도 한 번만 지워진다**(spec). 서버 한 행이 그 보장이다.

### 흐름 4. 줄을 눌러 대결로 가기

5.3 그대로. 알림함은 `battle_id`만 넘기고, 무엇을 보여 줄지는 **대결 상세가 가진 공개 규칙**이 정한다.

### 흐름 5. 알림함을 열어 둔 채 푸시가 도착

`PushService._handleForegroundMessage`가 `myBattlesProvider`·`battleDetailProvider`를 무효화하는 자리에 `notificationInboxProvider`·`hasNewNotificationsProvider`를 더한다. 알림함이 열려 있으면 목록이 다시 읽히고, 새 줄은 `_seenAtAtOpen`보다 나중이라 점이 붙는다.

### 흐름 6. 로그아웃·탈퇴

- 로그아웃: `MainShell`이 사라지며 두 provider가 버려진다. 서버에는 아무 일도 하지 않는다(읽음 시각은 계정의 값이다).
- 탈퇴: `delete_account`가 `notification_outbox`(내 수신 행)·`device_push_tokens`에 이어 `notification_reads` 행까지 지운다(1.3). 앱이 따로 할 일은 없다.

---

## 7. 개인정보 경계 — 알림함이 우회로가 되지 않는다

| 지켜야 할 것 | 어떻게 지켜지는가 |
|---|---|
| 내가 받을 알림만 읽힌다 | 세 함수 모두 `recipient_id = auth.uid()` / `user_id = auth.uid()`. **다른 사용자를 지정할 인자가 아예 없다.** 테이블에는 select 정책이 없어 직접 질의로는 0행 |
| 쓰기는 열지 않는다 | 원장에 insert/update/delete 정책이 없고, 앱이 부르는 세 함수 중 원장에 쓰는 것이 없다. 사건은 서버가 확정할 때만 생긴다 |
| payload 금지 키 | 적재 지점(사건 함수 6곳)을 **건드리지 않는다.** 판정 사유·사진 경로·상대 표시 이름은 앞으로도 payload에 담지 않는다. **앱 안에서만 쓸 값을 payload에 추가하지 않는다** — 그러면 "잠금화면에 나가도 되는 것"과 "앱 안에서만 보일 것"이 한 그릇에 섞여 담는 기준이 두 겹이 된다 |
| 상대 사진은 판정 창이 열린 뒤에만 | 알림함은 `object_path`를 **받지 않는다**(payload에 없고, 함수가 제출 테이블을 읽지 않는다). 사진을 보여 줄 재료가 구조적으로 없다 |
| 마감 전 상대에 대해 보이는 것은 "제출했다"는 사실 하나 | `submitted` payload는 `title`·`battle_type`뿐이다. 제출 시각·교체 횟수·유효 여부가 담기지 않으므로 알림함 줄도 그 이상을 말할 수 없다 |
| 판정 사유 노출 금지 | `judge_turn`·`finished`·`voided` payload에 `reason`·`verdict_reason`이 없다. 기존 스모크 테스트가 이미 "payload에 reason·object_path·display_name·winner_id가 없다"를 확인한다 |
| 발송 상태 비노출 | `list_notifications`가 `status`·`last_error`를 **돌려주지 않는다**(API 경계) |
| 잠금화면 정보량 | 알림함은 FCM 메시지·`notification_text.ts`를 한 글자도 바꾸지 않는다 → 잠금화면에 나가는 정보량이 그대로다 |
| 제3자 전적 조회 금지 | 알림함은 `profiles`·`player_stats`를 읽지 않는다. 상대 이름조차 쓰지 않는다 |

---

## 8. 클라이언트 파일 배치와 추가물

### 8.1 파일 배치 — 신규 feature 폴더 `lib/features/notification/`

```
lib/features/notification/
  data/
    notification_item.dart        // 원장 한 줄의 모델(id, kind, battleId, payload, createdAt) + fromMap
    notification_inbox.dart       // {seenAt, items} 묶음 모델
    notification_repository.dart  // RPC 3개(list / hasNew / markSeen)
  domain/
    notification_providers.dart   // notificationRepositoryProvider, notificationInboxProvider,
                                  // hasNewNotificationsProvider
    notification_line.dart        // kind+payload -> 줄 문구(순수 함수, 유닛 테스트 대상)
  presentation/
    notification_bell.dart        // 공용 종 버튼 + 점 배지(네 앱바가 쓴다)
    notification_inbox_screen.dart
```

- **`core/push`(배선)와 가르는 기준**: push는 화면이 없는 기기·플랫폼 배선이라 `core`에 있다. 알림함은 화면·레포지토리·모델·문구 매핑이 한 벌로 생기는 **기능**이라 feature 폴더가 맞다(CLAUDE.md의 `data/domain/presentation` 분할을 그대로 따른다).
- **`battle` 안에 넣지 않는 이유**: 입구가 네 탭 전부이고(대결 탭만의 것이 아니다) 할 일·프로필 화면도 이 위젯을 import한다. 다섯 번째 feature 폴더가 생기는 것은 CLAUDE.md 디렉토리 구조에 한 줄 적는다(9장).
- 네 탭 화면(`my_battles_screen.dart`, `battle_recruits_screen.dart`, `todo_list_screen.dart`, `profile_screen.dart`)은 **앱바에 한 줄씩**만 바뀐다.
- `main_shell.dart`는 (a) 탭 전환 리스너에 배지 invalidate 한 줄, (b) 앱 재개 리스너 추가. 그 외는 그대로다.
- **새 패키지 없음.** Material `Badge`·`AppLifecycleListener`는 Flutter 내장이다.

### 8.2 `AppIcons`에 더하는 것 (쓰는 자리가 생겼으므로)

```
bell          = Icons.notifications_rounded        // 네 앱바의 알림함 입구
bellOutlined  = Icons.notifications_none_rounded   // 알림함 빈 상태(빈 상태는 윤곽 변형 — 선례: emptyTodos)
judge         = Icons.gavel_rounded                // judge_turn 줄
```

나머지 kind는 기존 아이콘을 쓴다(4장 표). 얼굴·캐릭터·불꽃·하트·보석이 아니므로 `app_icons_test`의 IP 가드를 지난다.

### 8.3 구현 순서 제안 (최종 확정은 plan.md)

| 단계 | 스키마 변경 | 내용 |
|---|---|---|
| 1 | **있음(원격 적용 전 오너 확인)** | `notification_reads` + 인덱스 + RPC 3개 + `delete_account` 재정의, `supabase/tests/notification_inbox_smoke.sql` |
| 2 | 없음 | 레포지토리·provider·`notification_line.dart` + 유닛 테스트(앱 동작 변화 없음) |
| 3 | 없음 | 알림함 화면(커밋 하나) |
| 4 | 없음 | 공용 종 버튼 + 네 앱바 배선 + 배지 갱신 계기(탭 전환·앱 재개·포그라운드 푸시) |
| 5 | 없음 | 문서 정합(9장) |

"새 화면 하나 = 새 커밋 하나"(CLAUDE.md)를 지키기 위해 3·4를 가른다.

---

## 9. 문서 정합 — 코드와 어긋나게 될 문장들

| 어긋나는 문장 | 어디 | 어떻게 정리하는가 |
|---|---|---|
| "정책 없음: 서버 전용 함수만 이 테이블을 만진다 … **앱 안 알림함·읽음 표시는 spec 범위 밖이라 클라이언트가 이 테이블을 읽을 이유가 없다**" | `supabase/migrations/20260920120000_push_tokens_and_outbox.sql:91-92` (주석) | **옛 마이그레이션 파일은 고치지 않는다**(이미 원격에 적용된 파일을 사후 편집하면 적용본과 저장소가 어긋난다 — 이 저장소의 관행대로 "그 시점의 사실"로 남긴다). 대신 **새 마이그레이션 첫머리 주석에 그 문장을 인용하며 무엇이 바뀌었는지 적고**, `comment on table public.notification_outbox`를 `comment` 문으로 **갱신**한다: "… 클라이언트는 이 테이블을 직접 읽지 않는다. 수신자 본인의 조회는 list_notifications·has_new_notifications(security definer)만 통한다." 정책은 여전히 없으므로 **"서버 전용"이라는 사실 자체는 유지된다** — 바뀐 것은 "읽을 이유가 없다"뿐이다 |
| "범위 밖: 앱 안 알림함·읽음 표시" | `docs/specs/push-notification/spec.md` | 그 항목에 **한 줄 추기**: "2026-11-13에 뒤집혔다 — `docs/specs/notification-inbox/spec.md`(오너 확정)가 배포 전 최소 스코프로 넣기로 했다. 그 근거는 그 문서의 '왜 지금 범위 밖을 뒤집는가'에 있다." 문장을 지우지 않는 이유: 당시의 판단과 뒤집은 근거가 함께 보여야 다음에 같은 판단을 다시 할 수 있다 |
| `push-notification/design.md` "데이터 모델 › `notification_outbox` › RLS: … 클라이언트가 이 테이블을 읽을 이유가 없다" | 같은 문서 | 같은 방식으로 한 줄 추기(읽기는 notification-inbox가 definer 함수로 연다, 테이블 정책은 여전히 없다) |
| 알림 문구의 출처 규칙(= `strings.dart` 예외) | `CLAUDE.md` 코딩 규칙, `lib/core/strings.dart`의 알림 절 주석, `supabase/functions/_shared/notification_text.ts` 머리 주석 | **"푸시 문구(잠금화면)는 서버 `notification_text.ts`, 앱 안 알림함 줄은 `strings.dart` + `notification_line.dart`. 같은 kind를 같은 사실로 읽어야 하며, kind를 늘리면 두 자리를 함께 고친다."** 세 자리에 같은 뜻으로 한 줄씩 |
| "에러는 삼키지 않는다"의 예외 목록 | `CLAUDE.md` 코딩 규칙 | **"알림함 읽음 표시(`mark_notifications_seen`) 실패와 배지 조회(`has_new_notifications`) 실패도 `debugPrint`만 남긴다"** 추가. 이유를 함께 적는다 — 관문이 아니고, 사용자가 할 수 있는 일이 없고, 다음 열기에서 저절로 맞는다. **반대로 알림함 목록 조회 실패는 화면에 사실과 `다시 시도`를 보여 준다** |
| 범위 서술에 이 기능의 자리 | `CLAUDE.md` "현재 단계"의 배포 전 feature 목록 + 디렉토리 구조 | 배포 전 목록에 `notification-inbox`(순서: `push-notification` 6·7단계 뒤)를 넣고, 디렉토리 구조의 `features/`에 `notification/   # 앱 안 알림함` 한 줄 |
| 개인정보처리방침의 알림 원장 보유 기간 | 저장소 밖(`todododo-legal`) + `DEPLOY.md` 체크 항목 — **오너 몫** | push 7단계가 이미 "원장 행을 지우지 않는 것과 방침의 보유 기간이 어긋나지 않는지 확인"을 배정해 두었다. 알림함이 생기면 그 원장이 **"앱 안에서 사용자에게 보여 주는 기록"**이 되므로, 방침에 (a) 보관 항목(대결 제목·유형·결과·점수 변화 스냅샷), (b) 보유 기간(탈퇴 시 삭제, 그 전에는 보관), (c) 이용 목적에 "앱 안 알림함 표시"가 포함됨을 함께 적는다. **앱 안에서 보여 주는 범위는 50건이지만 보관은 전량**이라는 비대칭을 방침 문장이 틀리게 말하지 않도록 확인한다 |

---

## 10. 테스트

### 10.1 SQL 스모크 — `supabase/tests/notification_inbox_smoke.sql`

기존 틀 그대로: 임시 사용자·대결을 만들고 실제 함수를 부른 뒤 **마지막에 일부러 예외를 던져 전체를 롤백**한다. 결과는 `SMOKE RESULT ok=true` / `ok=false FAILURES: ...`. 사용자 전환은 선례대로 `perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true)`, 롤 전환은 `execute 'set local role anon'`.

**RLS·격리 (가장 중요)**
- [ ] A로 `list_notifications()` → **B가 받을 행이 하나도 없다**(B 전용 행을 미리 넣어 두고 id 집합을 비교).
- [ ] B로 `list_notifications()` → B 행만.
- [ ] `authenticated` 롤로 `select * from public.notification_outbox` → **0행**(정책 없음이 유지된다).
- [ ] `authenticated` 롤로 `select * from public.notification_reads` → **0행**.
- [ ] `authenticated` 롤로 원장 insert·update·delete → **전부 실패**(클라이언트가 원장에 쓸 수 없다).
- [ ] `anon` 롤로 세 RPC → 권한 오류. 로그인 없이(claims 없음) 호출 → `로그인이 필요합니다.`

**목록 내용**
- [ ] `status`가 `pending`·`sent`·`failed`·`dropped`인 행 네 개를 넣고 → **네 개 모두 보인다**(발송 상태 무관).
- [ ] 반환 항목의 키가 정확히 `id, kind, battle_id, payload, created_at`이다 — `status`·`attempts`·`last_error`·`lease_until`·`dedup_key`·`sent_at`·`recipient_id`가 **없다**.
- [ ] 60행을 넣으면 `items` 길이가 **50**이고, 들어 있는 것이 **가장 최신 50건**이다(가장 오래된 10건의 id가 없다).
- [ ] 정렬이 `created_at desc, id desc`다(같은 `created_at`인 두 행의 순서 확인).
- [ ] 7종 kind 전부를 넣어도 다 보인다(kind로 거르지 않는다).
- [ ] payload에 `reason`·`object_path`·`display_name` 키가 없다(기존 스모크와 같은 확인을 알림함 반환값에 대해 한 번 더).

**배지 판정**
- [ ] 행이 없는 신규 사용자 → `has_new_notifications()` = **false**.
- [ ] `notification_reads` 행이 없고 원장 행이 있으면 → **true**.
- [ ] `mark_notifications_seen()` 뒤 → **false**.
- [ ] 그 뒤 새 행을 넣으면 → **true**(= 경계가 `>` 비교라 같은 시각의 행에서 어긋나지 않는지도 함께 본다: `seen_at`과 **같은** `created_at`의 행은 새 알림이 **아니다**).
- [ ] `mark_notifications_seen()`을 두 번 불러도 `notification_reads`는 **한 행**이고 `seen_at`이 갱신된다.
- [ ] A가 읽음을 찍어도 B의 `has_new_notifications()`는 **true로 남는다**(계정별 값이다).

**탈퇴·정합**
- [ ] `delete_account()` 뒤 그 사용자의 `notification_reads` 행이 **0**이고, `notification_outbox`의 내 수신 행도 0이다(기존 동작 유지).
- [ ] 대결 행을 지우면(cascade) 그 대결의 알림 행도 사라진다 → `list_notifications()`에 안 보인다.

### 10.2 Dart 유닛 — `test/notification_line_test.dart`

`notification_line.dart`는 순수 함수다(`NotificationLine? notificationLine(String kind, Map<String, dynamic> payload)`).
- [ ] 7종 kind × 4장 매핑 표대로 사건 문구가 나온다.
- [ ] `finished`: `outcome` 5종(`win`/`draw`/`completed_loss`/`loss`/`forfeit`) × `score_delta` `+3`/`-1`/`0`. 0일 때 `점수 변화 없음`이고 `0점`이 아니다.
- [ ] `payload.title`이 없음·빈 문자열·공백만일 때 `대결`로 대체된다.
- [ ] **아는 키만 읽는다**: payload에 `reason`·`object_path`·`display_name`·`winner_id`를 일부러 넣어도 **어떤 줄에도 그 값이 나타나지 않는다**(서버 쪽 `notification_text_test.ts`의 같은 검사와 짝).
- [ ] 줄에 **남은 시간·기한 수치가 들어가지 않는다**(`deadline_at`·`judge_deadline_at`을 payload에 넣어도 문구에 숫자가 없다 — 원칙 4를 테스트로 묶는다).
- [ ] 모르는 kind → `null`.
- [ ] 시각 서식: `AppStrings.notificationTime(...)`이 `11월 8일 오후 3:04` 꼴이고, 자정·정오(오전 12시/오후 12시)와 분 한 자리(`3:04`) 경계가 맞다.

### 10.3 위젯 (선택 — MVP에서 강제하지 않음)

- [ ] `hasNewNotificationsProvider`를 `true`/`false`/`error`로 override → 점이 보임/안 보임/**안 보임**(실패에서 점을 그리지 않는다).
- [ ] 알림함: 빈 목록 → `아직 받은 알림이 없어요.`가 보이고 카드가 없다. 실패 → 문구 + `다시 시도`.
- [ ] 줄을 탭했을 때 `fetchBattle`이 실패하면 **상세가 열리지 않고** 토스트가 보인다(알림함에 머문다).
- [ ] 네 탭의 앱바에서 종 아이콘이 모두 보인다(`MainShell` 위젯 테스트에 탭을 오가며 확인).

### 10.4 실기기 확인(오너)

- [ ] 알림 권한을 **거부한** 계정으로 대결을 한 바퀴 돌린 뒤 알림함을 열면 사건들이 **모두 보인다**(전부 `dropped`인데 보인다 — 이 기능의 핵심 가치).
- [ ] 두 기기에 같은 계정으로 로그인 → 한쪽에서 알림함을 열면 다른 쪽도 점이 사라진다(앱 재개 또는 탭 전환 뒤).
- [ ] 알림함을 보는 동안 상대가 제출 → 목록에 줄이 늘어난다(포그라운드 처리).

---

## 11. 범위 밖(재확인)

삭제·전체 읽음 버튼·행별 읽음·안 읽음만 보기·필터·검색·종류별 설정·개수 배지·푸시 재발송·발송 상태 노출·공지/친구 알림·할 일 기한 알림·런처/홈 위젯 배지·더 보기/무한 스크롤·당겨서 새로고침(P1, 이 설계는 넣지 않는다)·알림함에서의 판정·제출·포기. **범위 밖을 위한 구조를 미리 만들지 않는다** — 특히 `notification_reads`에 "행별 읽음"을 대비한 컬럼·테이블을 두지 않고, RPC에 kind 필터·페이지 커서 인자를 두지 않는다.

---

## 결정 필요

**없음.** spec이 오너 확정으로 6항목을 닫았고, 남은 것들은 전부 설계 판단 범위였다.

다만 **설계가 스스로 고른 것 네 가지**를 적어 둔다. 오너가 뒤집고 싶으면 비용이 작은 자리들이다(묻지 않고 진행해도 되지만, 보고 지나가는 편이 낫다).

1. **알림함 줄 문구는 앱(`strings.dart` + 순수 매핑 함수)에서 만든다**(4장). 뒤집으면: 서버가 줄 문구까지 만들어 RPC로 내려 주게 되고, 문구를 고칠 때마다 마이그레이션·배포가 필요해진다.
2. **원장 읽기는 테이블 정책이 아니라 definer RPC 세 개로 연다**(2장). 뒤집으면: 정책 한 줄로 끝나지만 `status`·`last_error`가 앱 API에 열리고 50건 상한이 클라이언트 몫이 된다.
3. **알림함 출시 시점에 이미 쌓여 있던 행은 "새 알림"으로 본다**(= 첫 실행에서 점이 켜진다). 뒤집으면: 마이그레이션에서 기존 사용자에게 `seen_at = now()`를 미리 넣어 첫 점을 끈다. 그대로 두는 쪽을 고른 이유는 그 행들이 **정말로 사용자가 못 본 알림**이라는 것이고(특히 알림 권한을 거부한 사용자), 지금 영향받는 계정은 내부 테스트 계정뿐이다.
4. **당겨서 새로고침을 넣지 않는다**(spec P1). 뒤집으면 `RefreshIndicator` 한 겹이다. 넣지 않은 이유는 가장 가까운 선례(지난 대결 화면)에 없고, 화면을 닫고 열면 다시 읽히며 포그라운드 수신이 목록을 갱신하기 때문이다.
