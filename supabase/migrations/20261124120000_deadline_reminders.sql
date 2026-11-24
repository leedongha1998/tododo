-- push-notification 6단계: N6 마감 임박 알림.
--
-- 근거: docs/specs/push-notification/design.md "N6 마감 임박" 절과 그 2026-11-24 추기,
-- plan.md "6단계", docs/specs/bot-battle/design.md §9 "N6 인계".
--
-- design N6 절은 ai-judge 시절(기간 최소 24시간, 속도전 passed/failed·5회 제한)에 쓰였다.
-- 2026-11-24 오너 결정으로 아래 두 가지가 바뀌었다.
--   - 문턱: 마감 6시간 전 고정 -> **min(6시간, 기간의 절반)** 전. 기간이 분 단위(하한 1분)가 되어
--     6시간 고정이면 6시간 이하 대결은 매칭 직후에 "마감이 다가와요"가 온다. 1일 이상 대결은 종전대로
--     6시간 전, 1시간 대결은 30분 전, 봇전 5분 주제는 2분 30초 전이다.
--   - 대상: 마감 전 판정이 없어졌으므로(mutual-judge) 속도전의 "아직 통과 못 함"·"5회 소진 제외"가
--     없다. 두 유형 모두 **"이 대결에 내 제출 행이 아직 없다"** 하나다. 제출했으면(교체할 수 있든
--     없든) 대상이 아니다.
--
-- 봇전(battles.is_bot)도 대상이다(bot-battle spec: 일률 -1로 약해진 벌점을 메우는 장치가 N6이다).
--   - 수신자는 사람 참가자뿐이다. enqueue_notification의 봇 가드에 기대지 않고 선별 질의에서
--     user_id <> bot_user_id()로 직접 뺀다(이 함수는 enqueue_notification을 거치지 않는다 - 아래).
--   - **문턱은 기간에만 기댄다. 봇의 목표 시각 t_bot(봇 제출 행의 submitted_at)을 어떤 식으로도
--     읽지 않는다.** battle_submissions는 "이 사람의 행이 있는가"로만 읽고, 봇의 행은 수신자 조건에서
--     이미 빠진 사람의 것이라 어디에도 닿지 않는다.
--
-- 새 kind·새 문구는 없다. kind 'deadline_soon'은 원장 CHECK에 1단계부터 있고, 문구는 서버
-- notification_text.ts의 deadlineSoonText(분 단위 포함)와 앱 notification_line.dart가 이미 읽는다.
-- payload 키는 design "mutual-judge 반영"의 표 그대로 title·battle_type·deadline_at이다.
--
-- 마감 뒤 도착 금지는 claim_notifications의 기존 분기가 맡는다(20261103120000 재정의): 집어 드는
-- 순간 대결이 active가 아니거나 마감이 지났으면 dropped. 아주 짧은 대결(1분 등)은 cron 1분 주기라
-- 대개 문턱 구간을 지나쳐 쌓이지 않고, 쌓여도 마감 뒤에 집히면 그 분기가 내린다 - 따로 막지 않는다.
--
-- 인덱스를 새로 만들지 않는다. 바깥 조건(status = 'active' and deadline_at > now())은
-- battles_deadline_at_idx (deadline_at) where status = 'active'(20260921120100)가 받고, "제출 없음"은
-- battle_submissions_battle_user_unique (battle_id, user_id), 중복 방지는 원장의
-- unique (recipient_id, dedup_key)가 받는다.

-- ---------------------------------------------------------------------------
-- enqueue_deadline_reminders: 마감 임박인데 아직 내지 않은 참가자에게 N6을 쌓는다 (cron 1분)
-- ---------------------------------------------------------------------------
-- 권한 예외: cron 전용이라 CLAUDE.md의 auth.uid() 로그인 가드를 두지 않는다. cron에는 uid가 없어
-- 가드를 두면 항상 실패한다(선례: settle_expired_battles·dispatch_notifications). 앱·anon이 부를
-- 이유가 없으므로 public·anon·authenticated에서 EXECUTE를 회수하고 service_role에만 준다.
--
-- enqueue_notification을 행마다 부르지 않는 이유: 그 함수는 void라 "새로 쌓은 수"를 셀 수 없다.
-- 같은 방식(on conflict do nothing + 예외를 warning으로 삼킴)을 집합 insert 한 문장에 옮겼다.
--
-- 예외를 삼키는 이유(design 원칙 2): cron 명령 문자열 하나는 한 트랜잭션이라, 여기서 던지면 같은
-- 명령의 dispatch_notifications()가 돌지 않아 이미 쌓인 N1~N5까지 그 tick에 나가지 못한다. 실패하면
-- warning 하나를 남기고 0을 돌려준다. 다음 tick(1분 뒤)이 같은 대상을 다시 본다 - 문턱 구간은 대개
-- 수 분 이상이고, 놓쳐도 잃는 것은 알림 한 통이다(spec: 누락은 허용, 중복은 금지).
create function public.enqueue_deadline_reminders()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_count integer := 0;
begin
  begin
    insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload)
    select
      p.user_id,
      'deadline_soon',
      b.id,
      'deadline:' || b.id::text,
      jsonb_build_object(
        'title', b.title,
        'battle_type', b.type,
        'deadline_at', b.deadline_at
      )
    from public.battles b
    join public.battle_participants p on p.battle_id = b.id
    where b.status = 'active'
      and b.deadline_at is not null
      and b.deadline_at > now()
      -- 문턱: min(6시간, 기간의 절반). duration_minutes * 30초 = 기간의 절반.
      and now() >= b.deadline_at - least(interval '6 hours', b.duration_minutes * interval '30 seconds')
      -- 사람 참가자만. 봇은 기기도 알림함도 없다.
      and p.user_id <> public.bot_user_id()
      -- 아직 제출하지 않은 사람만. "이 사람의 행이 있는가"만 본다(시각·판정은 읽지 않는다).
      and not exists (
        select 1
        from public.battle_submissions s
        where s.battle_id = b.id
          and s.user_id = p.user_id
      )
    on conflict (recipient_id, dedup_key) do nothing;

    get diagnostics v_count = row_count;
  exception when others then
    raise warning '마감 임박 알림 적재 실패: %', sqlerrm;
    return 0;
  end;

  return v_count;
end;
$$;

comment on function public.enqueue_deadline_reminders is
  '마감까지 min(6시간, 기간의 절반) 이하가 남은 진행 중 대결에서 아직 제출하지 않은 사람 참가자에게 '
  '마감 임박 알림(deadline_soon)을 한 번씩 쌓고, 새로 쌓은 수를 돌려준다. 봇전도 대상이고 봇은 '
  '수신자가 아니며 봇의 목표 시각을 읽지 않는다. 실패해도 예외를 올리지 않는다(같은 cron 명령의 '
  '발송을 막지 않는다). cron 전용이라 로그인 가드를 두지 않는다(cron에는 auth.uid()가 없다).';

revoke execute on function public.enqueue_deadline_reminders() from public, anon, authenticated;
grant execute on function public.enqueue_deadline_reminders() to service_role;

-- ---------------------------------------------------------------------------
-- cron: notify-tick 명령 갱신 (1분 그대로)
-- ---------------------------------------------------------------------------
-- 같은 이름으로 cron.schedule을 다시 부르면 기존 작업이 **갱신**된다(중복 등록이 아니다). 작업 수는
-- 5개 그대로다(settle-expired-battles·ai-judge-tick·close-judging-windows·notify-tick·settle-bot-battles).
--
-- 적재를 발송 앞에 두는 이유: 같은 tick에서 쌓은 임박 알림이 그 tick의 발송으로 바로 나간다
-- (dispatch_notifications는 pending이 있을 때만 Edge를 깨운다). 판정 주기 작업들과는 여전히 다른
-- 작업이라 트랜잭션을 공유하지 않는다(4단계 주석 그대로).
select cron.schedule(
  'notify-tick',
  '* * * * *',
  $$select public.enqueue_deadline_reminders(); select public.dispatch_notifications();$$
);
