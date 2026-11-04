-- 발송 주기 작업 스모크 테스트 (push-notification 4단계 기준).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/notification_dispatch_smoke.sql
--
-- **실제 발송을 일으키지 않는다.** pending 행을 전부 지운 상태에서 부르므로 Vault 값이 들어와
-- 있든 없든 net.http_post까지 가지 않는다. 마지막에 예외를 던져 전체를 롤백하므로 지운 행도
-- 그대로 돌아온다.
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   보낼 것이 없으면 Edge를 깨우지 않는다(0 반환)
--   cron 작업 notify-tick이 1분 주기로 dispatch_notifications를 부른다
--   앱·anon은 dispatch_notifications를 부를 수 없다(cron 전용, service_role 권한은 선례와 같은 모양)
--   기존 주기 작업 네 개가 그대로 살아 있다(알림 작업이 판정 작업을 건드리지 않았다)
do $$
declare
  v_idle integer;
  v_job_schedule text;
  v_job_command text;
  v_job_active boolean;
  v_anon boolean;
  v_authenticated boolean;
  v_service boolean;
  v_other_jobs integer;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  -- 보낼 것이 없는 상태를 만든다(롤백되므로 실제로 지워지지 않는다).
  delete from public.notification_outbox where status = 'pending';

  v_idle := public.dispatch_notifications();

  select schedule, command, active
  into v_job_schedule, v_job_command, v_job_active
  from cron.job where jobname = 'notify-tick';

  v_anon := has_function_privilege('anon', 'public.dispatch_notifications()', 'execute');
  v_authenticated :=
    has_function_privilege('authenticated', 'public.dispatch_notifications()', 'execute');
  -- service_role은 Supabase가 기본으로 모든 함수에 EXECUTE를 준다. revoke from public, anon,
  -- authenticated로는 빠지지 않으므로(cron 전용 선례들도 전부 그렇다) "선례와 같은 모양인가"로 본다.
  v_service := has_function_privilege('service_role', 'public.dispatch_notifications()', 'execute')
    = has_function_privilege('service_role', 'public.settle_expired_battles()', 'execute');

  select count(*) into v_other_jobs
  from cron.job
  where jobname in ('ai-judge-tick', 'settle-expired-battles', 'close-judging-windows');

  v_actual := jsonb_build_object(
    'idle_returns_zero', v_idle,
    'job_schedule', v_job_schedule,
    'job_calls_dispatch', v_job_command like '%dispatch_notifications%',
    'job_active', v_job_active,
    'anon_execute', v_anon,
    'authenticated_execute', v_authenticated,
    'service_like_precedent', v_service,
    'other_jobs', v_other_jobs
  );

  v_expected := jsonb_build_object(
    'idle_returns_zero', 0,
    'job_schedule', '* * * * *',
    'job_calls_dispatch', true,
    'job_active', true,
    'anon_execute', false,
    'authenticated_execute', false,
    'service_like_precedent', true,
    'other_jobs', 3
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
