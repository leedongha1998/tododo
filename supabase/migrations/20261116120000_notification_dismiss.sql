-- notification-inbox 6단계: 누른 줄은 목록에서 사라진다.
--
-- 근거: docs/specs/notification-inbox/spec.md 맨 끝 "## 추가 (2026-11-16 오너)"
--       ("알림을 확인하면 걔는 리스트에서 지워주고 …"), 같은 폴더 design.md 12장.
--
-- ** 무엇이 뒤집혔는가 **
--   spec의 "범위 밖"에 있던 "알림 삭제" 중 **누른 줄 하나가 목록에서 사라지는 것만** 뒤집혔다.
--   스와이프 삭제·길게 눌러 메뉴·되돌리기·전체 지우기·원장 행 삭제는 범위 밖 그대로다.
--   원래의 근거("원장 행은 dedup 보장 때문에 지울 수 없고, 앱에서는 지워졌는데 서버에는 남아
--   있다는 두 겹 상태를 만들지 않는다")는 **원장을 건드리지 않는 방식**으로 지킨다 - 치운 것은
--   따로 적고 원장은 그대로 둔다.
--
-- ** 이 마이그레이션이 하지 않는 것 **
--   notification_outbox의 컬럼·제약·정책·인덱스를 건드리지 않는다. 사건 적재 함수
--   (join_battle·finalize_battle·void_battle·accept_submission·open_judging_window)도 그대로다.
--   읽음(notification_reads, 계정당 시각 하나)도 그대로다 - **치운 것과 읽은 것은 다른 축이다.**
--   치우지 않고 읽을 수 있고, 치운 뒤에도 새 알림은 또 온다. 그래서 배지는 여전히
--   "마지막으로 본 시각보다 새 행이 있는가"이고, 거기서 치운 줄만 빠진다.
--
--   20261113120000_notification_inbox.sql은 **이미 원격에 적용됐다.** 그 파일은 한 글자도 고치지
--   않고(적용본과 저장소가 어긋나지 않게) 여기서 create or replace로 갱신한다.

-- ---------------------------------------------------------------------------
-- 1. notification_dismissals: 내가 알림함에서 치운 줄
-- ---------------------------------------------------------------------------
-- 사용자 FK는 auth.users가 아니라 public.profiles다(CLAUDE.md). 탈퇴는 profiles 행을 묘비로
-- **남기므로** on delete cascade가 돌지 않는다 -> delete_account에서 명시적으로 지운다(아래 4장).
-- notification_id는 원장 행을 가리키고 on delete cascade다 - 대결이 지워지면 원장 행이 사라지고
-- (battle_id의 cascade) 그 줄을 치운 기록도 함께 사라진다. 가리킬 것이 없는 기록을 남기지 않는다.
create table public.notification_dismissals (
  user_id uuid not null references public.profiles (id) on delete cascade,
  notification_id bigint not null references public.notification_outbox (id) on delete cascade,
  dismissed_at timestamptz not null default now(),
  primary key (user_id, notification_id)
);

comment on table public.notification_dismissals is
  '알림함에서 치운 줄(내가 누른 줄). 목록·배지 조회가 이 행들을 빼고 돌려준다. '
  'notification_outbox에 컬럼을 더하지 않은 이유: 그 행은 dedup의 열쇠라 지울 수 없고, '
  '상태 컬럼을 더하면 발송 원장이 "앱에서 치웠는지"까지 아는 테이블이 된다 - 발송의 사실과 '
  '앱에서 치운 사실은 다른 축이다. 치운 사실은 notification_reads와 같은 결로 따로 적는다. '
  '쓰기 경로는 dismiss_notification 하나뿐이고 되돌리기(undo)는 만들지 않는다.';
comment on column public.notification_dismissals.dismissed_at is
  '서버 시각으로만 찍는다(클라이언트가 값을 보내지 않는다). 지금은 아무 질의도 이 값으로 거르지 '
  '않는다 - "언제 치웠나"를 설명해야 할 때를 위한 기록이다.';

-- notification_id 쪽 FK의 인덱스. 기본키 (user_id, notification_id)는 선두 축이 user_id라
-- 목록·배지 조회(두 축을 다 주는 질의)에는 충분하지만, **원장 행이 지워질 때 도는 cascade**는
-- notification_id만으로 찾는다 - 인덱스가 없으면 그때마다 전체 훑기가 된다(탈퇴는 내 수신 원장
-- 행을 통째로 지운다).
create index notification_dismissals_notification_idx
  on public.notification_dismissals (notification_id);

alter table public.notification_dismissals enable row level security;
-- 정책 없음: 아래 security definer 함수들만 이 테이블을 만진다(선례: notification_reads,
-- notification_outbox, quality_judgments). 화면은 "치운 줄 목록"을 쓸 일이 없다 - 목록 RPC가
-- 이미 빼고 돌려주므로 직접 select를 열 이유가 없고, "치운 알림 다시 보기"는 범위 밖이다.

-- ---------------------------------------------------------------------------
-- 2. dismiss_notification: 줄 하나를 치운다
-- ---------------------------------------------------------------------------
-- 앱이 부르는 RPC라 CLAUDE.md 규칙 그대로다: security definer + search_path 고정,
-- 첫 줄 auth.uid() 가드, revoke from public, anon + grant to authenticated.
--
-- ** 내 몫의 행만 치울 수 있다. ** 원장에 그 id가 있고 recipient_id = auth.uid()일 때만 넣고,
-- 아니면 **조용히 아무 것도 하지 않는다**(예외를 던지지 않는다). 남의 알림 id를 넣어 보는 것으로
-- "그 id가 있는가"를 알아낼 수 없어야 한다 - 없는 id와 남의 id의 반응이 같다.
--
-- 멱등이다(on conflict do nothing). 같은 줄을 두 번 눌러도 한 행이고, 되돌리기는 없다.
create function public.dismiss_notification(p_notification_id bigint)
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

  insert into public.notification_dismissals (user_id, notification_id)
  select v_user, o.id
  from public.notification_outbox o
  where o.id = p_notification_id
    and o.recipient_id = v_user
  on conflict (user_id, notification_id) do nothing;
end;
$$;

comment on function public.dismiss_notification is
  '알림함에서 줄 하나를 치운다(내가 수신자인 행만, 멱등). 남의 알림 id나 없는 id에는 조용히 '
  '아무 것도 하지 않는다 - 존재 여부를 알려 주지 않는다. 원장 행은 지우지 않는다.';

-- ---------------------------------------------------------------------------
-- 3. 목록·배지에서 치운 줄을 뺀다 (create or replace)
-- ---------------------------------------------------------------------------
-- 20261113120000의 정의를 그대로 두고 where에 not exists 한 조각만 더한다. 반환 키·상한 50·
-- 정렬·발송 상태 무관은 전부 그대로다.
--
-- ** 50건은 "치운 것을 뺀 뒤의 최근 50건"이다. ** not exists를 limit **안쪽** 질의에 두는 이유가
-- 그것이다 - 밖에서 걸러내면 치운 줄이 50칸 중 한 자리를 차지해 목록이 점점 짧아진다.
create or replace function public.list_notifications()
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

  -- 정렬을 aggregate 안에서 한 번 더 적는다(안쪽 order by는 "어느 50건을 고르는가", 밖은
  -- "배열에 담기는 순서"). 앱은 받은 순서를 그대로 쓰므로 이 순서가 계약이다.
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
      -- 내가 치운 줄은 빠진다. 치움은 계정별이라 상대의 알림함은 그대로다.
      and not exists (
        select 1
        from public.notification_dismissals d
        where d.user_id = v_user
          and d.notification_id = o.id
      )
    order by o.created_at desc, o.id desc
    limit 50
  ) picked;

  return jsonb_build_object('seen_at', v_seen, 'items', v_items);
end;
$$;

comment on function public.list_notifications is
  '내가 받을 알림 최근 50건 + 마지막으로 알림함을 본 시각. 치운 줄은 빠지고, 50건은 치운 것을 '
  '뺀 뒤의 수다. 발송 상태로 거르지 않고 발송 상태를 돌려주지도 않는다. 다른 사용자를 지정할 '
  '인자가 없다.';

-- 배지도 치운 줄을 세지 않는다. 실제로는 치우려면 먼저 알림함을 열어야 해서(= 읽음이 찍혀서)
-- 값이 달라지는 경우가 거의 없지만, "치운 줄이 점을 켜지 않는다"가 더 분명하다.
create or replace function public.has_new_notifications()
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

  -- 행이 하나도 없는 신규 가입자는 false다. 경계는 > 비교다 - seen_at과 **같은** created_at의
  -- 행은 새 알림이 아니다(앱의 NotificationItem.isNewSince와 같게 둔다).
  return exists (
    select 1
    from public.notification_outbox o
    where o.recipient_id = v_user
      and o.created_at > coalesce(
        (select r.seen_at from public.notification_reads r where r.user_id = v_user),
        '-infinity'::timestamptz
      )
      and not exists (
        select 1
        from public.notification_dismissals d
        where d.user_id = v_user
          and d.notification_id = o.id
      )
  );
end;
$$;

comment on function public.has_new_notifications is
  '마지막으로 알림함을 본 시각보다 나중에 생긴 내 알림이 있는가(치운 줄은 세지 않는다). '
  '개수를 세지 않는다(배지는 점 하나).';

-- Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 주므로 revoke를 함께 쓴다(CLAUDE.md).
-- 갱신한 두 함수는 create or replace라 기존 GRANT가 그대로 남는다(여기서 다시 주지 않는다).
revoke execute on function public.dismiss_notification(bigint) from public, anon;
grant execute on function public.dismiss_notification(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. delete_account: notification_dismissals 한 줄 추가
-- ---------------------------------------------------------------------------
-- **20261113120000_notification_inbox.sql의 정의(가장 늦은 정의)를 그대로 복사하고 7번 단계에
-- 한 줄만 끼워 넣었다.** 열 번 넘게 재정의된 함수라 옛 정의를 베끼면 기준 증서·동의 기록·알림
-- 토큰·읽음 시각 삭제가 조용히 되살아나거나 사라진다. 인자 없는 시그니처는 그대로이고
-- create or replace라 GRANT도 그대로 남는다. 다른 동작은 한 줄도 바꾸지 않았다.
--
-- 왜 cascade에 맡기지 않는가: notification_dismissals의 user_id FK는 public.profiles를
-- 가리키는데(CLAUDE.md) 탈퇴는 profiles 행을 "탈퇴한 사용자" 묘비로 **남기므로** cascade가 돌지
-- 않는다. (notification_id FK 쪽은 돈다 - 바로 위에서 내 수신 원장 행을 지우기 때문이다. 그래도
-- 명시적으로 지우는 편이 순서에 기대지 않아 안전하다.)
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
  --    치운 기록도 함께(치움은 계정의 값이다).
  delete from public.notification_dismissals where user_id = v_user_id;

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
