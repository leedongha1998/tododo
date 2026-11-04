-- push-notification 4단계: 발송 경로(주기 작업 -> Edge Function).
--
-- 근거: docs/specs/push-notification/design.md "발송 경로 - 기존 구조 재사용 검토", "데이터 흐름"
-- 흐름 2, "API 계약 > RPC - 서버 전용"의 dispatch_notifications, plan.md 4단계.
--
-- 핵심 규칙
--   - 발송은 대결 진행을 절대 막지 못한다. 이 작업은 판정 주기 작업과 **다른 cron 작업**이라
--     트랜잭션을 공유하지 않는다 - 여기서 예외가 나도 ai-judge-tick·settle-expired-battles·
--     close-judging-windows는 그대로 돈다.
--   - 값(주소·비밀값)은 Vault에 이름으로만 둔다. 마이그레이션·코드·로그 어디에도 값이 남지 않는다.
--     **값이 없으면 아무것도 보내지 않고 0을 반환한다** - 원장은 그대로 쌓여 값이 들어온 순간부터
--     이어서 나간다(선례: dispatch_ai_judgments).
--   - 보낼 것이 없으면 Edge를 깨우지 않는다. 1분마다 도는 작업이라 빈 호출이 쌓이면 그만큼 낭비다.
--
-- 이 단계는 원장에 행을 넣지 않는다(3단계가 넣는다). 마감 임박(N6)은 6단계가 같은 tick의 앞에
-- enqueue_deadline_reminders()를 더해 붙인다.

-- ---------------------------------------------------------------------------
-- dispatch_notifications: 보낼 알림이 있으면 Edge를 한 번 깨운다 (cron 1분)
-- ---------------------------------------------------------------------------
-- 권한 예외: cron 전용이라 CLAUDE.md의 auth.uid() 로그인 가드를 두지 않는다. cron에는 uid가 없어
-- 가드를 두면 항상 실패한다(선례: settle_expired_battles·dispatch_ai_judgments). Edge가 부르는
-- 함수가 아니므로 service_role에도 주지 않고 EXECUTE를 전부 회수한다.
--
-- 한 번만 부르는 이유: Edge가 claim_notifications로 한 묶음(50행)을 집어 비운다. 남은 것은 다음
-- tick이 이어서 비우므로 여기서 행 수만큼 부를 이유가 없다(잡 단위로 부르는 dispatch_ai_judgments와
-- 다른 점이다 - 저기는 잡 하나가 호출 하나다).
create function public.dispatch_notifications()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_pending integer;
  v_url text;
  v_secret text;
begin
  select count(*) into v_pending from public.notification_outbox where status = 'pending';

  if v_pending = 0 then
    return 0;
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'notify_function_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'notify_cron_secret';

  if v_url is null or v_secret is null then
    -- 아직 값이 들어오지 않았다. 원장은 그대로 남으므로 값이 들어오는 순간부터 이어서 나간다.
    return 0;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notify-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );

  return v_pending;
end;
$$;

comment on function public.dispatch_notifications is
  '보낼 알림이 있으면 발송 Edge Function을 한 번 깨운다(Vault 값이 없으면 아무것도 하지 않는다). '
  'cron 전용이라 로그인 가드를 두지 않는다(cron에는 auth.uid()가 없다).';

revoke execute on function public.dispatch_notifications() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- cron: notify-tick (1분)
-- ---------------------------------------------------------------------------
-- 판정 주기 작업(ai-judge-tick)에 붙이지 않는 이유: 알림 쪽에서 예외가 나면 그 tick의 판정까지
-- 되돌아간다. 작업을 나누면 트랜잭션이 갈라져 서로를 막지 못한다(design "발송 경로" 검토표).
--
-- 1분 주기인 이유: 사건 확정과 도착 사이의 지연을 1분 안으로 묶고, 6단계가 더할 마감 임박
-- 판단(6시간 문턱)의 정확도를 ±1분으로 두기 위함이다.
--
-- 같은 이름으로 cron.schedule을 다시 부르면 기존 작업이 **갱신**된다(중복 등록이 아니다).
-- 6단계가 이 명령 문자열 앞에 enqueue_deadline_reminders()를 더한다.
select cron.schedule(
  'notify-tick',
  '* * * * *',
  $$select public.dispatch_notifications();$$
);
