-- notification-inbox 1단계: 앱 안 알림함의 읽기 경로와 읽음 상태.
--
-- 근거: docs/specs/notification-inbox/spec.md(2026-11-13 오너 확정 6항목),
--       같은 폴더 design.md 1장(데이터 모델)·2장(읽기를 어떻게 여는가)·3장(API 계약)·9장(문서 정합).
--
-- ** 뒤집히는 문장 **
--   20260920120000_push_tokens_and_outbox.sql은 notification_outbox에 이렇게 적었다 —
--   "정책 없음: 서버 전용 함수만 이 테이블을 만진다(선례: quality_judgments).
--    앱 안 알림함·읽음 표시는 spec 범위 밖이라 클라이언트가 이 테이블을 읽을 이유가 없다."
--   2026-11-13에 오너가 앱 안 알림함을 배포 전 범위로 확정해 **뒤 문장만** 뒤집혔다. 옛 파일은
--   그 시점의 사실로 그대로 남기고(이미 원격에 적용됐다) 여기서 comment만 갱신한다.
--   **"정책 없음"은 유지된다** — 읽기를 여는 자리는 테이블이 아니라 아래 security definer 함수
--   셋이다(design 2장 C안). 그래서 "클라이언트가 못 만지는 테이블"이라는 구조적 보장이 남고,
--   검증해야 할 면이 테이블 전체가 아니라 함수 셋으로 좁아진다.
--
-- ** 이 마이그레이션이 하지 않는 것 **
--   사건 적재 함수(join_battle·finalize_battle·void_battle·accept_submission·open_judging_window)는
--   한 줄도 건드리지 않는다. 알림함은 읽기 전용 거울이라 쌓는 쪽에 닿지 않는다(design 원칙 1).
--   payload 키·kind 체크 제약·notification_outbox의 컬럼과 정책도 그대로다.
--   delete_account만 재정의한다 — profiles 행이 묘비로 남아 cascade가 돌지 않기 때문이다.

-- ---------------------------------------------------------------------------
-- 1. notification_outbox: 인덱스 하나와 주석 갱신 (컬럼·제약·정책 변경 없음)
-- ---------------------------------------------------------------------------
-- 알림함과 배지가 보는 축. 기존 인덱스는 (created_at) where status = 'pending'(발송기용)이라
-- 수신자별 최신 조회에 쓸 수 없고, unique (recipient_id, dedup_key)는 정렬에 쓸 수 없다.
--
-- id desc를 함께 두는 이유: created_at의 기본값 now()는 **트랜잭션 시작 시각**이라 같은
-- 트랜잭션에서 한 수신자에게 두 행이 생기면 값이 같다(판정 창이 열릴 때가 그렇다).
-- 정렬이 흔들리지 않게 깨뜨릴 축을 하나 더 둔다.
create index notification_outbox_recipient_idx
  on public.notification_outbox (recipient_id, created_at desc, id desc);

comment on table public.notification_outbox is
  '알림 발송 원장. 사건 지점이 한 행을 넣고 발송기가 비운다. 행은 지우지 않는다(dedup_key가 '
  '살아 있어야 한 사건을 한 번만 알린다). 2026-11-13부터 이 행들은 앱 안 알림함에도 보인다 - '
  '다만 클라이언트는 이 테이블을 직접 읽지 않는다(정책이 하나도 없다). 수신자 본인의 조회는 '
  'list_notifications·has_new_notifications(security definer)만 통하고, 그 함수들이 돌려주는 '
  '컬럼은 화이트리스트다(status·attempts·last_error·lease_until·dedup_key는 앱에 가지 않는다).';

-- ---------------------------------------------------------------------------
-- 2. notification_reads: 알림함을 마지막으로 본 시각 (계정당 한 행)
-- ---------------------------------------------------------------------------
-- profiles에 컬럼으로 두지 않는 이유(design 1.2):
--   profiles에는 "누구나 조회" select 정책(using (true))이 있어 컬럼을 더하면 "이 사람이 마지막으로
--   알림을 확인한 시각"이 로그인한 모든 사용자에게 공개된다. 게다가 본인 행 update 정책이 있어
--   클라이언트가 그 값을 직접 쓸 수 있다 - 미래 시각을 넣으면 배지가 영구히 꺼지고 과거로 되돌리면
--   영구히 켜진다. 시각의 주인은 서버여야 한다(CLAUDE.md "승부 기준 시각은 언제나 서버 시각").
--   player_stats에 얹지 않는 이유는 그 테이블의 쓰기가 finalize_battle 하나라는 규칙 때문이다.
--
-- 사용자 FK는 auth.users가 아니라 public.profiles다(CLAUDE.md). 다만 탈퇴는 profiles 행을 묘비로
-- 남기므로 cascade가 돌지 않는다 -> delete_account에서 명시적으로 지운다(아래 4장).
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
-- 행이 없는 사용자 = 한 번도 알림함을 열지 않은 사용자다. 별도 플래그를 두지 않는다.

-- ---------------------------------------------------------------------------
-- 3. 읽기 RPC 세 개
-- ---------------------------------------------------------------------------
-- 셋 다 앱이 부르는 RPC라 CLAUDE.md 규칙 그대로다: security definer + search_path 고정,
-- 첫 줄 auth.uid() 가드, revoke from public, anon + grant to authenticated.
-- 새 오류 코드·hint를 만들지 않는다 - 실패는 예외 문구 하나다.

-- 알림함 화면이 여는 유일한 조회. 상한 50은 서버 상수다(인자를 두지 않는다 - 클라이언트가 범위를
-- 늘릴 수 있으면 "최근 50건"이 서버의 보장이 아니게 된다).
--
-- 돌려주는 키는 화이트리스트다: status·attempts·last_error·lease_until·dedup_key·sent_at·
-- recipient_id는 담지 않는다. 발송 상태는 사용자가 할 수 있는 일이 없고(spec "발송 상태를 사용자에게
-- 보여 주지 않는다"), last_error는 FCM이 준 서버 오류 문자열이다. UI 규율이 아니라 API 경계로 막는다.
--
-- **발송 상태로 거르지 않는다.** 알림 권한을 거부한 사용자의 행은 전부 dropped이므로, 보낸 것만
-- 보여 주면 그 사용자의 알림함이 영원히 빈다 - 그것이 이 기능의 핵심 가치다. 거르지 않겠다는 결정을
-- "status를 읽지도 않는 것"으로 표현한다. 대결 상태로도 거르지 않는다(끝난·무효·취소된 대결의
-- 알림도 보인다).
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

  -- 정렬을 **aggregate 안에서 한 번 더** 적는다. 안쪽 order by는 "어느 50건을 고르는가"를 정하고
  -- (limit과 짝이다), 밖의 order by는 "배열에 담기는 순서"를 보장한다 - 하위 질의의 정렬이
  -- 집계로 그대로 넘어온다는 보장은 없다. 앱은 받은 순서를 그대로 쓰므로(다시 정렬하지 않는다)
  -- 이 순서가 계약이다.
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', picked.id,
               'kind', picked.kind,
               'battle_id', picked.battle_id,
               'payload', picked.payload,
               'created_at', picked.created_at
             )
             order by picked.created_at desc, picked.id desc
           ),
           '[]'::jsonb
         ) into v_items
  from (
    select o.id, o.kind, o.battle_id, o.payload, o.created_at
    from public.notification_outbox o
    where o.recipient_id = v_user
    order by o.created_at desc, o.id desc
    limit 50
  ) picked;

  -- seen_at을 목록과 **같은 호출에서** 돌려준다. 두 번 나눠 물으면 그 사이에 찍히는 값 때문에
  -- "새 알림" 표시가 어긋날 수 있고, 화면은 이 스냅샷 하나로 새/읽음을 가른다(design 5.2).
  return jsonb_build_object('seen_at', v_seen, 'items', v_items);
end;
$$;

comment on function public.list_notifications is
  '내가 받을 알림 최근 50건 + 마지막으로 알림함을 본 시각. 발송 상태로 거르지 않고 발송 상태를 '
  '돌려주지도 않는다. 다른 사용자를 지정할 인자가 없다.';

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

  -- 행이 하나도 없는 신규 가입자는 false다(spec "알림을 처음 받기 전에는 새 알림 표시가 없다").
  -- 경계는 > 비교다 - seen_at과 **같은** created_at의 행은 새 알림이 아니다.
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

comment on function public.has_new_notifications is
  '마지막으로 알림함을 본 시각보다 나중에 생긴 내 알림이 있는가. 개수를 세지 않는다(배지는 점 하나).';

-- 알림함을 열었다. 시각은 서버가 찍는다(인자 없음). 멱등이라 두 번 불러도 행이 늘지 않는다.
-- "전체 읽음 처리" 버튼은 만들지 않는다 - 여는 것이 곧 읽음이다(spec).
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

comment on function public.mark_notifications_seen is
  '알림함을 본 시각을 서버 시각으로 찍는다(계정당 한 행, 멱등). 클라이언트가 시각을 보내지 않는다.';

-- Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 주므로 revoke를 함께 쓴다(CLAUDE.md).
revoke execute on function public.list_notifications() from public, anon;
grant execute on function public.list_notifications() to authenticated;
revoke execute on function public.has_new_notifications() from public, anon;
grant execute on function public.has_new_notifications() to authenticated;
revoke execute on function public.mark_notifications_seen() from public, anon;
grant execute on function public.mark_notifications_seen() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. delete_account: notification_reads 한 줄 추가
-- ---------------------------------------------------------------------------
-- **20261106120000_remove_battle_limits.sql의 정의(가장 늦은 정의)를 그대로 복사하고 7번 단계에
-- 한 줄만 끼워 넣었다.** 열 번 넘게 재정의된 함수라 옛 정의를 베끼면 기준 증서·동의 기록·알림 토큰
-- 삭제나 슬롯 제거가 조용히 되살아난다. 인자 없는 시그니처는 그대로이고 create or replace라
-- GRANT도 그대로 남는다.
--
-- 왜 cascade에 맡기지 않는가: notification_reads의 FK는 public.profiles를 가리키는데(CLAUDE.md)
-- 탈퇴는 profiles 행을 "탈퇴한 사용자" 묘비로 **남기므로** on delete cascade가 돌지 않는다.
create or replace function public.delete_account()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_cancelled_ids uuid[];
  v_cancelled record;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 1. 끝나지 않은 대결은 승자·점수 변화 없이 취소한다. 속도전에서 이미 통과했어도 취소다(결정 42).
  with cancelled as (
    update public.battles
    set status = 'cancelled', finished_at = now()
    where status in ('pending', 'active', 'judging')
      and (creator_id = v_user_id or opponent_id = v_user_id)
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_cancelled_ids from cancelled;

  -- N5. 남은 상대에게만. 상대가 없는 pending 모집은 알릴 사람이 없다(other_id가 null).
  -- 탈퇴한 사람의 이름은 담지 않는다. 한도가 없어졌으므로 "한도가 돌아왔다"는 말도 하지 않는다.
  for v_cancelled in
    select b.id,
           b.title,
           case when b.creator_id = v_user_id then b.opponent_id else b.creator_id end as other_id
    from public.battles b
    where b.id = any (v_cancelled_ids)
  loop
    perform public.enqueue_notification(
      v_cancelled.other_id,
      'cancelled',
      v_cancelled.id,
      'cancelled:' || v_cancelled.id::text,
      jsonb_build_object('title', v_cancelled.title)
    );
  end loop;

  -- 판정 대기 중이던 AI 재판정 잡. 대결이 취소됐으므로 판정할 것이 없다.
  delete from public.ai_judgment_jobs where battle_id = any (v_cancelled_ids);

  -- 2. 개인 투두.
  delete from public.todos where user_id = v_user_id;

  -- 3. 증거 사진 경로는 개인 데이터라 끊는다. 사진 파일은 앱이 이 RPC 직전에 Storage API로 지운다.
  --    제출 행 자체와 사유·시각은 남은 상대의 전적을 설명하는 판정 기록이라 남긴다.
  update public.battle_submissions
  set object_path = null
  where user_id = v_user_id;

  -- 4. 점수. 묘비 사용자의 점수는 공개 대상이 아니다.
  delete from public.player_stats where user_id = v_user_id;

  -- 5. 기준 증서와 호출 원장. 대결이 성립하기 전의 초안이라 보존할 이유가 없다.
  delete from public.criteria_checks where user_id = v_user_id;
  delete from public.ai_criteria_calls where user_id = v_user_id;

  -- 6. 동의·철회 기록. 탈퇴 후에는 남기지 않는다(decisions 68).
  delete from public.ai_consent_events where user_id = v_user_id;
  delete from public.ai_consents where user_id = v_user_id;

  -- 7. 알림 토큰과 내가 받을 알림. 개인정보처리방침의 "탈퇴 시 삭제"와 맞춘다.
  --    내가 수신자인 행만 지운다 - 상대가 받을 알림(방금 적재한 N5 포함)은 상대의 기록이다.
  delete from public.device_push_tokens where user_id = v_user_id;
  delete from public.notification_outbox where recipient_id = v_user_id;
  --    알림함 읽음 시각도 함께. FK가 profiles라 묘비가 남는 탈퇴에서는 cascade가 돌지 않는다.
  delete from public.notification_reads where user_id = v_user_id;

  -- 8. 묘비화.
  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 9. 실제 계정 삭제. 0행이면 "데이터만 지워지고 계정은 살아있는" 상태를 막기 위해 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;
