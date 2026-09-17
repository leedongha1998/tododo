-- push-notification 1단계: 기기 알림 토큰과 알림 발송 원장.
--
-- 근거: docs/specs/push-notification/design.md "데이터 모델", "API 계약", "구현 단계 분할" 1단계,
-- spec.md "P0. 기기·로그아웃·탈퇴", "P0. 실패했을 때의 태도", design 결정 3(원장 행은 지우지 않는다).
--
-- 핵심 규칙
--   - 알림은 이미 확정된 사실의 사본이다. 이 마이그레이션은 판정·점수·상태 전이를 한 줄도 바꾸지 않는다.
--   - 발송은 대결 진행을 절대 막지 못한다. 사건 트랜잭션에서는 HTTP를 부르지 않고 원장에 한 행만 넣으며,
--     그 insert조차 enqueue_notification 안의 예외 블록에서 삼킨다(아래 주석 참고).
--   - 한 사건은 한 번만 알린다. unique (recipient_id, dedup_key)가 물리적으로 막는다.
--   - 잠금화면에 나갈 수 있는 것만 원장에 담는다. 판정 사유·사진 경로·상대 표시 이름은 payload에 넣지 않는다
--     (그 규칙을 지키는 것은 3단계의 사건 지점이고, 이 단계는 담을 그릇만 만든다).
--
-- 이 단계에서 앱 동작은 전혀 바뀌지 않는다. 아무도 아직 원장에 넣지 않고(3단계), 아무도 비우지 않는다(4단계).

-- ---------------------------------------------------------------------------
-- device_push_tokens: 기기 알림 토큰 (신규)
-- ---------------------------------------------------------------------------
-- token을 PK로 두는 이유: 같은 기기에 다른 계정으로 로그인하면 같은 토큰이 다시 등록된다.
-- PK + on conflict do update로 소유자가 교체되므로, 기기를 물려받은 사람에게 남의 알림이 가지 않는다.
-- 한 계정 여러 기기 = user_id가 같은 행 여러 개("주 기기" 개념을 만들지 않는다).
-- 플랫폼 컬럼은 두지 않는다 - 안드로이드만이다(CLAUDE.md "iOS 대응 금지", 미래 대비 추상화 금지).
create table public.device_push_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index device_push_tokens_user_idx on public.device_push_tokens (user_id);

comment on table public.device_push_tokens is
  '기기 알림(FCM) 토큰. 로그인된 기기마다 한 행. 쓰기는 register_push_token / unregister_push_token만.';
comment on column public.device_push_tokens.token is
  'FCM 등록 토큰(앱 설치 단위로 유일). PK라서 같은 기기에 다른 계정이 로그인하면 소유자가 교체된다.';
comment on column public.device_push_tokens.last_seen_at is
  '앱이 열릴 때마다 등록 RPC가 갱신한다. 원인 추적용이고, 만료 판단은 FCM 응답이 한다(이 값으로 하지 않는다).';

alter table public.device_push_tokens enable row level security;

-- select는 본인 행만. insert/update/delete 정책은 두지 않는다 -> 쓰기는 아래 RPC만(선례: ai_consents).
create policy "users can view their own push tokens"
  on public.device_push_tokens for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- notification_outbox: 알림 발송 원장 (신규)
-- ---------------------------------------------------------------------------
-- payload는 사건이 확정되는 트랜잭션에서 만든 스냅샷이다. 발송(Edge)은 DB를 다시 읽지 않으므로
-- 발송 시점에 값이 바뀌어도 문구가 흔들리지 않고, Edge가 대결·제출 테이블에 접근할 이유가 없어
-- 비공개 정보(판정 사유·사진)가 새는 경로 자체가 없다.
--
-- 발송 뒤에도 행을 지우지 않는다(status만 바뀐다). dedup_key가 계속 살아 있어야 "이미 보냈다"가
-- 영구히 남는다 - 행을 지우는 순간 "한 사건은 한 번만"이 깨진다(design 결정 3). 그래서 정리 작업을 두지 않는다.
create table public.notification_outbox (
  id bigserial primary key,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null
    constraint notification_outbox_kind_check
      check (kind in ('matched', 'finished', 'voided', 'quality_submitted',
                      'speed_verdict', 'cancelled', 'deadline_soon')),
  battle_id uuid not null references public.battles (id) on delete cascade,
  dedup_key text not null,
  payload jsonb not null,
  status text not null default 'pending'
    constraint notification_outbox_status_check
      check (status in ('pending', 'sending', 'sent', 'failed', 'dropped')),
  attempts smallint not null default 0,
  lease_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  constraint notification_outbox_dedup_unique unique (recipient_id, dedup_key)
);

-- 발송 주기 작업이 보는 것은 pending 행뿐이다.
create index notification_outbox_pending_idx
  on public.notification_outbox (created_at) where status = 'pending';

comment on table public.notification_outbox is
  '알림 발송 원장. 사건 지점이 한 행을 넣고 발송기가 비운다. 행은 지우지 않는다(dedup_key가 살아 있어야 한 사건을 한 번만 알린다).';
comment on column public.notification_outbox.dedup_key is
  '사건 식별자. unique (recipient_id, dedup_key) + on conflict do nothing으로 중복 발송을 물리적으로 막는다.';
comment on column public.notification_outbox.status is
  'pending(발송 대기) / sending(임대 중) / sent(최소 한 기기에 전달) / failed(시도했으나 실패, 재시도 없음) / dropped(보낼 이유가 사라짐 - 토큰 없음, 마감 지난 임박 알림, 종결된 대결).';
comment on column public.notification_outbox.payload is
  '사건 확정 시점의 스냅샷. 판정 사유·사진 경로·상대 표시 이름은 담지 않는다(잠금화면에 그대로 보인다).';

alter table public.notification_outbox enable row level security;
-- 정책 없음: 서버 전용 함수만 이 테이블을 만진다(선례: quality_judgments).
-- 앱 안 알림함·읽음 표시는 spec 범위 밖이라 클라이언트가 이 테이블을 읽을 이유가 없다.

-- ---------------------------------------------------------------------------
-- enqueue_notification: 사건 지점이 부르는 단 하나의 적재 경로
-- ---------------------------------------------------------------------------
-- 내부 전용이라 SECURITY INVOKER로 두고 EXECUTE를 모두 회수한다(선례: finalize_battle·void_battle).
-- 호출자는 모두 SECURITY DEFINER 함수라 실효 사용자가 테이블 소유자가 되어 RLS를 지나간다.
--
-- ** 예외를 삼키는 이유(design 원칙 2) **
--   알림 원장 insert가 실패해도 그 사건 트랜잭션(판정·종결·점수 반영)은 커밋되어야 한다. 여기서
--   예외가 밖으로 나가면 알림이 판정을 되돌리는 셈이 되고, 이는 spec "알림 발송 실패가 대결 진행을
--   막지 않는다"에 정면으로 어긋난다. 그래서 전체를 예외 블록(= 서브트랜잭션)으로 감싸고 raise warning
--   으로 서버 로그만 남긴다. CLAUDE.md "에러는 삼키지 않는다"를 어기는 것이 아니라 "로그는 남기고
--   사용자에게는 알리지 않는다"에 해당한다 - 사용자가 할 수 있는 일이 없고, 그 시점에 앱을 보고 있지도 않다.
create function public.enqueue_notification(
  p_recipient_id uuid,
  p_kind text,
  p_battle_id uuid,
  p_dedup_key text,
  p_payload jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- 받을 사람이나 대결이 없으면 알릴 것이 없다(예: 상대가 없는 pending 모집). 조용히 지나간다.
  if p_recipient_id is null or p_battle_id is null then
    return;
  end if;

  begin
    insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload)
    values (p_recipient_id, p_kind, p_battle_id, p_dedup_key, coalesce(p_payload, '{}'::jsonb))
    on conflict (recipient_id, dedup_key) do nothing;
  exception when others then
    -- 판정을 되돌리지 않는다. 운영자가 보는 로그만 남긴다.
    raise warning '알림 적재 실패 (kind=%, battle=%): %', p_kind, p_battle_id, sqlerrm;
  end;
end;
$$;

comment on function public.enqueue_notification is
  '알림 원장에 한 행을 넣는다(중복은 무시). 내부 전용. 실패해도 예외를 올리지 않고 warning만 남긴다 - 알림이 판정 트랜잭션을 되돌리지 못하게 하는 장치다.';

-- ---------------------------------------------------------------------------
-- register_push_token / unregister_push_token: 앱이 부르는 RPC
-- ---------------------------------------------------------------------------
-- 멱등이라 앱이 열릴 때마다 불러도 된다. on conflict do update가 소유자를 교체하므로
-- 기기를 물려받은 사람에게 이전 사용자의 알림이 가지 않는다(spec "로그아웃한 기기에는 오지 않는다").
create function public.register_push_token(p_token text)
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

  if p_token is null or length(trim(p_token)) = 0 then
    raise exception '알림 토큰이 필요합니다.';
  end if;

  if length(p_token) > 4096 then
    raise exception '알림 토큰이 너무 깁니다.';
  end if;

  insert into public.device_push_tokens (token, user_id)
  values (p_token, v_user)
  on conflict (token) do update
    set user_id = excluded.user_id,
        last_seen_at = now();
end;
$$;

comment on function public.register_push_token is
  '이 기기의 알림 토큰을 내 것으로 등록한다(멱등). 같은 토큰이 다른 계정에 있었으면 소유자를 교체한다.';

-- 로그아웃 직전에 부른다(세션이 살아 있어야 auth.uid()가 나온다). 남의 토큰은 지우지 못한다.
create function public.unregister_push_token(p_token text)
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

  delete from public.device_push_tokens
  where token = p_token and user_id = v_user;
end;
$$;

comment on function public.unregister_push_token is
  '이 기기의 알림 토큰 등록을 해제한다(내 행만). 로그아웃 직전에 부른다.';

-- ---------------------------------------------------------------------------
-- claim_notifications: 보낼 알림을 임대해 간다 (Edge send-notifications)
-- ---------------------------------------------------------------------------
-- 권한 예외: Edge Function(service_role) 전용이라 CLAUDE.md의 auth.uid() 로그인 가드를 두지 않는다.
-- 서비스 롤에는 uid가 없어 가드를 두면 항상 실패한다(선례: settle_expired_battles·accept_submission·
-- claim_quality_judgment). 대신 public·anon·authenticated에서 EXECUTE를 모두 회수하고 service_role에만 준다.
--
-- 토큰이 0개인 수신자의 행을 dropped로 내리는 이유: 알림을 거부했거나 로그아웃한 사용자의 행이 영원히
-- pending으로 남으면 tick마다 다시 집어 든다. 애초에 발송을 시도하지 않으므로 "알림 권한이 없는
-- 사용자에게 보내려다 생기는 오류가 사용자에게 노출되지 않는다"는 수용 기준도 여기서 지켜진다.
create function public.claim_notifications(p_limit integer default 50)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_rows jsonb;
begin
  -- (1) 임대가 만료된 발송은 실패로 내린다. 재시도하지 않는다 - spec은 누락을 허용하고 중복을 금지한다.
  update public.notification_outbox
  set status = 'failed',
      lease_until = null,
      last_error = coalesce(last_error, '발송 임대가 만료되었습니다.')
  where status = 'sending'
    and lease_until is not null
    and lease_until <= now();

  -- (2) 보낼 이유가 사라진 행을 폐기한다.
  update public.notification_outbox o
  set status = 'dropped',
      lease_until = null
  where o.status = 'pending'
    and (
      -- 받을 기기가 하나도 없다(알림 거부·로그아웃·기기 정리).
      not exists (
        select 1 from public.device_push_tokens t where t.user_id = o.recipient_id
      )
      -- 마감 임박 알림은 마감이 지났거나 대결이 더는 진행 중이 아니면 보내지 않는다
      -- (spec: 마감이 지난 뒤에 "마감이 다가온다"는 알림이 오지 않는다).
      or (
        o.kind = 'deadline_soon'
        and not exists (
          select 1 from public.battles b
          where b.id = o.battle_id
            and b.status = 'active'
            and b.deadline_at > now()
        )
      )
    );

  -- (3) 남은 pending을 임대한다. skip locked라 발송기가 겹쳐 돌아도 한 행을 한 번만 집는다.
  with picked as (
    select o.id
    from public.notification_outbox o
    where o.status = 'pending'
    order by o.created_at, o.id
    limit greatest(coalesce(p_limit, 50), 1)
    for update skip locked
  ),
  leased as (
    update public.notification_outbox o
    set status = 'sending',
        attempts = o.attempts + 1,
        lease_until = now() + interval '2 minutes'
    where o.id in (select id from picked)
    returning o.id, o.kind, o.battle_id, o.payload, o.recipient_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', l.id,
        'kind', l.kind,
        'battle_id', l.battle_id,
        'payload', l.payload,
        'tokens', coalesce(
          (select jsonb_agg(t.token order by t.created_at, t.token)
           from public.device_push_tokens t
           where t.user_id = l.recipient_id),
          '[]'::jsonb)
      )
      order by l.id
    ),
    '[]'::jsonb)
  into v_rows
  from leased l;

  return v_rows;
end;
$$;

comment on function public.claim_notifications is
  '보낼 알림을 임대해 반환한다(서버 전용). 임대 만료분은 failed로, 받을 기기가 없거나 마감이 지난 임박 알림은 dropped로 정리한다.';

-- ---------------------------------------------------------------------------
-- record_notification_result: 발송 결과를 기록하고 죽은 토큰을 정리한다
-- ---------------------------------------------------------------------------
-- 권한 예외 이유는 claim_notifications와 같다(Edge 전용이라 auth.uid()가 없다).
create function public.record_notification_result(
  p_id bigint,
  p_status text,
  p_error text default null,
  p_dead_tokens text[] default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  -- dropped는 claim_notifications가 정하는 상태다. 발송기는 보냈는지 실패했는지만 말한다.
  if p_status is distinct from 'sent' and p_status is distinct from 'failed' then
    raise exception '알 수 없는 발송 결과입니다.';
  end if;

  -- sending인 행만 고친다. 임대가 만료돼 이미 failed로 내려간 행에 늦게 도착한 결과가 덮어쓰지
  -- 못하게 한다(ai-judge의 "늦게 도착한 판정은 조용히 버린다"와 같은 처리).
  update public.notification_outbox
  set status = p_status,
      lease_until = null,
      sent_at = case when p_status = 'sent' then now() else sent_at end,
      last_error = case when p_status = 'sent' then null else left(p_error, 500) end
  where id = p_id and status = 'sending';

  -- FCM이 더 이상 유효하지 않다고 답한 토큰은 지운다. 사용자가 따로 할 일은 없다(spec).
  if p_dead_tokens is not null and array_length(p_dead_tokens, 1) > 0 then
    delete from public.device_push_tokens where token = any (p_dead_tokens);
  end if;
end;
$$;

comment on function public.record_notification_result is
  '발송 결과(sent | failed)를 기록하고 죽은 토큰을 지운다(서버 전용). 임대 중인 행만 대상이다.';

-- ---------------------------------------------------------------------------
-- delete_account: 내 알림 토큰과 내 수신 원장도 함께 지운다
-- ---------------------------------------------------------------------------
-- 20260919120000_quality_judgments.sql의 정의를 그대로 유지한 create or replace이고(인자 없는
-- 시그니처도 그대로), 7번 단계만 새로 끼워 넣었다. profiles 행은 묘비로 남으므로 on delete cascade가
-- 돌지 않아 알림 토큰을 명시적으로 지워야 한다(design "데이터 모델").
create or replace function public.delete_account()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_cancelled_ids uuid[];
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

  -- 매칭된 날이 오늘(KST)인 슬롯만 지워 남은 상대의 오늘 한도를 돌려준다(결정 49·63).
  delete from public.daily_battle_slots
  where battle_id = any (v_cancelled_ids)
    and kst_date = (now() at time zone 'Asia/Seoul')::date;

  -- 판정 대기 중이던 품질전 잡. 대결이 취소됐으므로 판정할 것이 없다.
  delete from public.quality_judgments where battle_id = any (v_cancelled_ids);

  -- 2. 개인 투두.
  delete from public.todos where user_id = v_user_id;

  -- 3. 증거 사진 경로는 개인 데이터라 끊는다. 사진 파일은 앱이 이 RPC 직전에 Storage API로 지운다.
  --    제출 행 자체와 사유·시각은 남은 상대의 전적을 설명하는 판정 기록이라 남긴다.
  update public.battle_submissions
  set object_path = null
  where user_id = v_user_id;

  -- 4. 한도 원장과 점수. 묘비 사용자의 점수는 공개 대상이 아니다.
  delete from public.daily_battle_slots where user_id = v_user_id;
  delete from public.player_stats where user_id = v_user_id;

  -- 5. 기준 증서와 호출 원장. 대결이 성립하기 전의 초안이라 보존할 이유가 없다.
  delete from public.criteria_checks where user_id = v_user_id;
  delete from public.ai_criteria_calls where user_id = v_user_id;

  -- 6. 동의·철회 기록. 탈퇴 후에는 남기지 않는다(decisions 68).
  delete from public.ai_consent_events where user_id = v_user_id;
  delete from public.ai_consents where user_id = v_user_id;

  -- 7. 알림 토큰과 내가 받을 알림. 개인정보처리방침의 "탈퇴 시 삭제"와 맞춘다
  --    (push-notification spec "탈퇴하면 그 계정의 알림 등록 정보가 함께 사라진다").
  --    내가 수신자인 행만 지운다 - 상대가 받을 알림은 상대의 기록이라 건드리지 않는다.
  delete from public.device_push_tokens where user_id = v_user_id;
  delete from public.notification_outbox where recipient_id = v_user_id;

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

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
-- 내부 전용: 아무 롤도 부를 수 없다(호출자는 3단계에서 배선하는 SECURITY DEFINER 사건 함수들이다).
revoke execute on function public.enqueue_notification(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;

-- Edge Function(service_role) 전용. 로그인 가드 대신 authenticated까지 회수한다(위 주석의 예외).
revoke execute on function public.claim_notifications(integer) from public, anon, authenticated;
revoke execute on function public.record_notification_result(bigint, text, text, text[])
  from public, anon, authenticated;
grant execute on function public.claim_notifications(integer) to service_role;
grant execute on function public.record_notification_result(bigint, text, text, text[]) to service_role;

-- 앱이 부르는 RPC. Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 주므로 함께 회수한다.
revoke execute on function public.register_push_token(text) from public, anon;
grant execute on function public.register_push_token(text) to authenticated;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;
