-- mutual-judge 2단계: 판정 창, 속도전 제출 교체, 참가자 상호 판정 기록, 자동 승인, 결론 규칙.
--
-- 근거: docs/specs/mutual-judge/spec.md(오너 승인 2026-09-18), design.md "상태 전이", "데이터 모델",
-- "공개 범위와 RLS", "제출 교체와 경합", "주기 작업", "버리는 것의 실제 제거 계획", "API 계약".
--
-- 핵심 규칙
--   - 제출 즉시 AI 판정이 사라진다. 판정은 제출이 더 이상 바뀔 수 없게 된 뒤(양쪽 제출 또는 마감)
--     열리는 판정 창(status = 'judging')에서 참가자끼리 한다. 두 유형 공통이다.
--   - 판정 창은 열린 시각 + 24시간이다. 기한이 지나면 판정하지 않은 사람은 승인한 것으로 본다.
--   - 속도전은 상대가 아직 제출하지 않은 동안 사진을 바꿀 수 있고, 바꾸면 submitted_at이 다시 찍힌다.
--     품질전에는 교체가 없다.
--   - 마감 전에는 상대의 제출 시각·사진·통과 여부를 어떤 쿼리로도 얻을 수 없다. 보이는 것은
--     battle_participants.has_submitted(제출했다는 사실) 하나다.
--   - 승패는 참가자 판정·AI 재판정이라는 사실로 DB 순수 함수가 정한다. 클라이언트는 계산하지 않는다.
--
-- 이 단계에 없는 것(3단계): AI 재판정 잡. 이 단계만 적용된 동안 불복(reject)이나 품질전 우열 불일치가
-- 생긴 대결은 judging에 머문다. 앱에 판정 화면이 아직 없어(4단계) 앱 경로로는 생기지 않고, 3단계의
-- resolve_battle이 다음 판정 창 닫기 tick에서 잡을 만들어 이어받는다.
-- quality_judgments 테이블과 그 함수들(claim/record/dispatch)도 3단계에서 지운다. 이 단계 이후로는
-- 잡을 만드는 곳도 부르는 곳도 없다(accept_submission이 더 이상 만들지 않고 cron에서 dispatch를 뺐다).
--
-- 적용 직후 submit-evidence Edge Function을 재배포해야 한다. 배포된 옛 함수는 이 파일이 지우는
-- record_speed_verdict를 부르므로 그 사이 속도전 제출이 실패한다.

-- ---------------------------------------------------------------------------
-- 적용 전 확인: 옛 규칙으로 진행 중인 대결이 없어야 한다
-- ---------------------------------------------------------------------------
-- 아래에서 지우는 컬럼(제출 status, 5회 이력)에 기대는 진행 중 대결은 새 규칙으로 옮길 방법이 없다.
-- 조용히 고치지 않고 적용 자체를 멈춘다. 종결된 대결은 옮길 필요가 없지만, 참가자당 제출 1행
-- 제약을 걸어야 하므로 옛 속도전 시도 이력(한 사람이 여러 행)이 남아 있으면 역시 멈춘다.
do $$
begin
  if exists (select 1 from public.battles where status = 'judging') then
    raise exception '판정 중(judging)인 대결이 있어 적용할 수 없습니다. 먼저 정리하세요.';
  end if;

  if exists (
    select 1
    from public.battle_submissions s
    join public.battles b on b.id = s.battle_id
    where b.status = 'active'
  ) then
    raise exception '제출이 있는 진행 중 대결이 있어 적용할 수 없습니다. 먼저 정리하세요.';
  end if;

  if exists (
    select 1 from public.battle_submissions
    group by battle_id, user_id
    having count(*) > 1
  ) then
    raise exception '한 참가자의 제출이 여러 행인 대결이 있어 적용할 수 없습니다. 먼저 정리하세요.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- battles: 판정 창 컬럼
-- ---------------------------------------------------------------------------
-- judge_deadline_at은 창이 열린 시각 + 24시간이다(design 결정 사항 1). timestamptz + interval은
-- STABLE이라 generated column으로 둘 수 없어, open_judging_window가 같은 문장에서 함께 기록한다.
alter table public.battles
  add column judging_opened_at timestamptz,
  add column judge_deadline_at timestamptz;

alter table public.battles
  add constraint battles_judging_window_pair_check
    check ((judging_opened_at is null) = (judge_deadline_at is null)),
  add constraint battles_judging_has_window_check
    check (status <> 'judging' or judging_opened_at is not null);

comment on column public.battles.status is
  'pending(모집 중) -> active(매칭됨, 제출 창) -> judging(상호 판정 창, 두 유형 공통) -> finished(승자 있음) | draw | voided(불복·불일치 AI 재판정이 끝내 실패) | cancelled. '
  '아무도 제출하지 않았거나 품질전 한쪽만 제출했으면 judging 없이 끝난다. disputed는 유료 재심용 개념으로만 남고 MVP에서 도달하지 않는다.';
comment on column public.battles.judging_opened_at is
  '판정 창이 열린 서버 시각. null이면 아직 제출 창이다. 이 값이 서면 양쪽 제출 행과 증거 사진이 서로에게 공개된다.';
comment on column public.battles.judge_deadline_at is
  '판정 기한(판정 창이 열린 시각 + 24시간). 지나면 판정하지 않은 사람은 승인한 것으로 본다.';
comment on column public.battles.verdict_reason is
  '품질전 우열 AI 재판정의 한 줄 사유. 그 판정이 곧바로 종결시키므로 종결과 동시에 양쪽에 공개된다. '
  '최소 기준 재판정 사유는 제출 행(battle_submissions.reason)에 남는다.';

-- 1분 주기 cron 두 개가 테이블 전체를 훑지 않게 한다.
create index battles_judge_deadline_idx
  on public.battles (judge_deadline_at) where status = 'judging';
create index battles_active_deadline_idx
  on public.battles (deadline_at) where status = 'active';

-- ---------------------------------------------------------------------------
-- battle_participants: 진행 중 상대에게 보여도 되는 요약만 남긴다
-- ---------------------------------------------------------------------------
-- 이 테이블은 참가자 둘 다 읽는다(정책 "participants can view their battle progress"가 행의 user_id를
-- 보지 않는다 — design "battle_participants의 노출은 확인된 사실이다"). 그래서 지금 있던
-- first_submitted_at(상대의 제출 시각), last_verdict(상대의 합격/불합격), passed_at(상대의 통과 시각)이
-- 상대에게 그대로 새고 있었다. 정책을 좁히지 않고 컬럼을 불린 두 개로 바꾼다.
alter table public.battle_participants
  drop column first_submitted_at,
  drop column attempts_used,
  drop column last_verdict,
  drop column passed_at;

alter table public.battle_participants
  add column has_submitted boolean not null default false,
  add column has_judged boolean not null default false;

comment on table public.battle_participants is
  '대결 참가자별 진행 요약과 결과. 이 테이블의 모든 컬럼은 상대 참가자도 읽는다. 진행 중 상대에게 보여도 되는 요약만 둔다. '
  '시점에 따라 가려야 하는 값(제출 시각·사진·판정 내용)은 battle_submissions·battle_judgments·Storage에 둔다.';
comment on column public.battle_participants.has_submitted is
  '증거 사진을 제출했는지. 시각을 담지 않는다 — 시각이 보이면 속도전 승부가, 값이 바뀌면 교체 횟수가 새어 나간다.';
comment on column public.battle_participants.has_judged is
  '판정 창에서 상대 증거를 판정했는지(판정 기한이 지나 자동 승인된 경우 포함). 판정 내용은 담지 않는다.';
comment on policy "participants can view their battle progress" on public.battle_participants is
  '참가자는 자기 행과 상대 행을 모두 읽는다. 이 테이블의 모든 컬럼은 상대 참가자도 읽는다. 진행 중 상대에게 보여도 되는 요약만 둔다.';

-- ---------------------------------------------------------------------------
-- battle_submissions: 참가자당 한 행, 교체는 덮어쓰기
-- ---------------------------------------------------------------------------
-- 교체를 새 행으로 남기면 행 수가 곧 교체 횟수라 판정 창이 열릴 때 상대에게 드러나고, 버킷에 옛 사진이
-- 쌓인다. 덮어쓰고 옛 사진은 Edge가 지운다.
drop index public.battle_submissions_one_judging_idx;
drop index public.battle_submissions_one_passed_idx;
drop index public.battle_submissions_one_quality_idx;

-- 유니크 제약이 같은 열 순서의 인덱스를 만들므로 옛 일반 인덱스는 중복이다.
drop index public.battle_submissions_battle_user_idx;

alter table public.battle_submissions
  drop column status,
  drop column judging_started_at;

alter table public.battle_submissions
  add column verdict_source text
    constraint battle_submissions_verdict_source_check
      check (verdict_source in ('opponent', 'auto', 'ai'));

-- 종결된 옛 대결에 남은 결론은 전부 AI가 낸 것이다(옛 규칙에는 사람 판정이 없었다).
update public.battle_submissions set verdict_source = 'ai' where meets_criteria is not null;

alter table public.battle_submissions
  add constraint battle_submissions_one_per_user unique (battle_id, user_id),
  -- 결론과 그 결론을 누가 냈는지는 함께 생기고 함께 비어 있다.
  add constraint battle_submissions_verdict_pair_check
    check ((meets_criteria is null) = (verdict_source is null));

comment on table public.battle_submissions is
  '증거 사진 제출. 참가자당 한 행이고 속도전 교체는 이 행을 덮어쓴다. 판정 창이 열리기 전에는 본인 행만 보이고, '
  '창이 열리거나 대결이 끝나면 상대 행이 열린다.';
comment on column public.battle_submissions.submitted_at is
  '서버 수신 시각. 속도전 승부 기준. 교체하면 다시 찍힌다(먼저 눌러 시각을 선점하고 나중에 바꾸는 것을 막는다).';
comment on column public.battle_submissions.meets_criteria is
  '최소 기준 결론. 상대의 승인·판정 기한 경과 자동 승인이면 true, 불복당했으면 AI 재판정 결과. 미결이면 null.';
comment on column public.battle_submissions.verdict_source is
  'meets_criteria를 누가 정했나: opponent(상대가 승인) | auto(판정 기한 경과 자동 승인) | ai(불복 후 AI 재판정).';
comment on column public.battle_submissions.reason is
  'AI 재판정의 한 줄 사유. 사람의 판정에는 사유가 없다.';

drop policy "users can view own submissions or finished battle submissions" on public.battle_submissions;

-- 내 제출은 언제든. 상대 제출은 판정 창이 열린 뒤(양쪽 증거가 동시에 공개된다) 또는 종결 뒤.
-- 종결 상태 목록은 창 없이 끝난 대결(제출 0건 draw, 품질전 한쪽 제출 승리, 포기, 취소)을 덮는다.
-- 참가자 비교는 등호 두 개로 쓴다. 비로그인이면 둘 다 null이라 통과하지 않는다.
create policy "users can view own submissions or revealed battle submissions"
  on public.battle_submissions for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.battles b
      where b.id = battle_id
        and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
        and (b.judging_opened_at is not null
             or b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed'))
    )
  );

-- ---------------------------------------------------------------------------
-- battle_judgments: 참가자 상호 판정 기록 (신규)
-- ---------------------------------------------------------------------------
-- 판정 대상 컬럼을 두지 않는다. 2인 대결이라 대상은 항상 judge_id의 상대다.
-- superior_id는 '나/상대'가 아니라 사용자 id로 적는다 — 두 사람의 답이 같은 사람을 가리키는지
-- 비교할 때 뒤집기 실수가 생기지 않는다.
create table public.battle_judgments (
  battle_id uuid not null references public.battles (id) on delete cascade,
  judge_id uuid not null references public.profiles (id) on delete cascade,
  min_verdict text not null
    constraint battle_judgments_min_verdict_check check (min_verdict in ('approve', 'reject')),
  superior_id uuid references public.profiles (id),
  auto boolean not null default false,
  decided_at timestamptz not null default now(),
  primary key (battle_id, judge_id),
  -- 자동 승인은 승인이고 우열을 채우지 않는다(채우면 "한쪽만 답함" 규칙이 깨지고 불필요한 AI 호출이 생긴다).
  constraint battle_judgments_auto_shape_check
    check (not auto or (min_verdict = 'approve' and superior_id is null))
);

comment on table public.battle_judgments is
  '판정 창에서 참가자가 상대 증거에 내린 판정. 한 사람당 한 번(PK)이고 되돌릴 수 없다. '
  '판정 창 중에는 본인 판정만 보이고, 대결이 끝나면 상대 판정도 열린다. 쓰기는 submit_judgment와 서버 전용 함수만.';
comment on column public.battle_judgments.min_verdict is
  '상대 사진이 최소 기준을 통과했는가: approve(승인) | reject(불복 → AI 재판정). disputed 상태와 섞이지 않게 dispute라는 말을 쓰지 않는다.';
comment on column public.battle_judgments.superior_id is
  '품질전에서 더 잘했다고 고른 사람(두 참가자 중 하나). 속도전과 자동 승인 행은 null.';
comment on column public.battle_judgments.auto is
  '판정 기한이 지나 서버가 승인으로 채운 행.';

alter table public.battle_judgments enable row level security;

-- 판정 창 중에 상대의 판정 내용이 보이면 상대 답을 보고 내 답을 고르는 경로가 생긴다.
-- insert/update/delete 정책은 두지 않는다.
create policy "judges can view own judgments or finished battle judgments"
  on public.battle_judgments for select
  to authenticated
  using (
    judge_id = auth.uid()
    or exists (
      select 1 from public.battles b
      where b.id = battle_id
        and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
        and b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed')
    )
  );

-- ---------------------------------------------------------------------------
-- 판정 규칙 순수 함수
-- ---------------------------------------------------------------------------
-- 옛 규칙(제출 즉시 AI, 5회 상한, 두 사진이 모이면 AI)이 박힌 함수를 지우고 새 규칙으로 바꾼다.
-- 참가자 a/b는 호출부에서 a = creator, b = opponent로 고정 매핑한다.
-- 데이터를 읽지 않지만 앱이 부를 이유도 없으므로 EXECUTE를 전부 회수한다(SECURITY DEFINER가 아니므로
-- 로그인 가드 규칙 대상이 아니다).
drop function public.speed_outcome(timestamptz, bigint, integer, boolean, timestamptz, bigint, integer, boolean, boolean);
drop function public.quality_outcome(boolean, boolean, text);
drop function public.quality_deadline_outcome(boolean, boolean);

-- 판정 창을 열지 결정한다.
--   open: 판정 창을 연다 / wait: 아직 제출 창 / finish_a·finish_b: 그 사람 승리로 바로 종결(품질전
--   한쪽 제출) / draw: 아무도 내지 않았다.
create function public.judging_gate(
  p_type text,
  p_a_submitted boolean,
  p_b_submitted boolean,
  p_deadline_passed boolean
)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_a boolean := coalesce(p_a_submitted, false);
  v_b boolean := coalesce(p_b_submitted, false);
begin
  if p_type is distinct from 'speed' and p_type is distinct from 'quality' then
    raise exception '대결 유형이 올바르지 않습니다: %', p_type;
  end if;

  -- 양쪽이 내면 사진이 둘 다 잠겨 결과가 더 바뀔 수 없다. 마감을 기다리지 않는다.
  if v_a and v_b then
    return 'open';
  end if;

  if not coalesce(p_deadline_passed, false) then
    return 'wait';
  end if;

  if not v_a and not v_b then
    return 'draw';
  end if;

  -- 속도전 한쪽 제출: 그 사진이 기준을 통과했는지는 아직 아무도 판정하지 않았다.
  -- 판정할 사람은 제출하지 않은 상대다.
  if p_type = 'speed' then
    return 'open';
  end if;

  -- 품질전 한쪽 제출: 판정할 상대 증거가 없어 제출자가 바로 이긴다.
  return case when v_a then 'finish_a' else 'finish_b' end;
end;
$$;

comment on function public.judging_gate is
  '판정 창 열림 규칙(순수 함수). a = creator, b = opponent. open | wait | finish_a | finish_b | draw.';

-- 제출 하나의 최소 기준 결론.
--   p_opponent_verdict: 이 제출에 대한 상대의 판정(approve | reject | null=아직 안 함)
--   p_ai_meets: 불복 뒤 AI 재판정 결과(없으면 null)
create function public.min_verdict_effect(
  p_submitted boolean,
  p_opponent_verdict text,
  p_ai_meets boolean
)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if not coalesce(p_submitted, false) then
    return 'none';
  end if;

  if p_opponent_verdict is null then
    return 'pending';
  end if;

  if p_opponent_verdict = 'approve' then
    return 'pass';
  end if;

  if p_opponent_verdict = 'reject' then
    -- AI가 사람의 불복을 대체한다. 거짓 불복은 여기서 뒤집혀 이득이 되지 않는다.
    return case
      when p_ai_meets is null then 'pending'
      when p_ai_meets then 'pass'
      else 'fail'
    end;
  end if;

  raise exception '판정 값이 올바르지 않습니다: %', p_opponent_verdict;
end;
$$;

comment on function public.min_verdict_effect is
  '제출별 최소 기준 결론(순수 함수). none(제출 없음) | pending(판정·AI 대기) | pass | fail.';

-- 속도전 결론. 유효한 완료(pass) 중 서버 제출 시각이 이른 쪽이 이긴다.
-- 하나라도 pending이면 결정하지 않고 전부 null을 돌려준다(호출부가 기다린다).
create function public.mutual_speed_outcome(
  p_a_effect text,
  p_a_at timestamptz,
  p_a_seq bigint,
  p_b_effect text,
  p_b_at timestamptz,
  p_b_seq bigint,
  out status text,
  out winner text,
  out a_outcome text,
  out b_outcome text
)
language plpgsql
immutable
set search_path = public
as $$
declare
  v_a_pass boolean := p_a_effect = 'pass';
  v_b_pass boolean := p_b_effect = 'pass';
begin
  if p_a_effect = 'pending' or p_b_effect = 'pending' then
    return;
  end if;

  if v_a_pass and v_b_pass then
    status := 'finished';
    -- 동률이면 먼저 기록된 제출(id가 작은 쪽).
    if p_a_at < p_b_at or (p_a_at = p_b_at and p_a_seq < p_b_seq) then
      winner := 'a';
      a_outcome := 'win';
      b_outcome := 'completed_loss';
    else
      winner := 'b';
      a_outcome := 'completed_loss';
      b_outcome := 'win';
    end if;
    return;
  end if;

  if v_a_pass then
    status := 'finished';
    winner := 'a';
    a_outcome := 'win';
    b_outcome := 'loss';
    return;
  end if;

  if v_b_pass then
    status := 'finished';
    winner := 'b';
    a_outcome := 'loss';
    b_outcome := 'win';
    return;
  end if;

  -- 유효한 완료가 하나도 없다(불합격·미제출 조합).
  status := 'draw';
  a_outcome := 'draw';
  b_outcome := 'draw';
end;
$$;

comment on function public.mutual_speed_outcome is
  '속도전 결론(순수 함수). a = creator, b = opponent. pass끼리는 이른 submitted_at(동률이면 작은 id)이 승리, 패자는 completed_loss. pending이 있으면 전부 null.';

-- 품질전 결론. 최소 기준을 먼저 적용하고, 둘 다 통과했을 때만 우열 답을 쓴다.
--   p_*_pick: 그 사람이 더 잘했다고 고른 슬롯('a' | 'b' | null=판정 안 함)
--   next: finish | draw | ai(우열 불일치, AI가 가른다) | wait(최소 기준 미결)
create function public.mutual_quality_outcome(
  p_a_effect text,
  p_b_effect text,
  p_a_pick text,
  p_b_pick text,
  out next text,
  out status text,
  out winner text,
  out a_outcome text,
  out b_outcome text
)
language plpgsql
immutable
set search_path = public
as $$
declare
  v_a_pass boolean := p_a_effect = 'pass';
  v_b_pass boolean := p_b_effect = 'pass';
  v_pick text;
begin
  if p_a_effect = 'pending' or p_b_effect = 'pending' then
    next := 'wait';
    return;
  end if;

  if v_a_pass and not v_b_pass then
    next := 'finish';
    status := 'finished';
    winner := 'a';
    a_outcome := 'win';
    b_outcome := 'loss';
    return;
  end if;

  if v_b_pass and not v_a_pass then
    next := 'finish';
    status := 'finished';
    winner := 'b';
    a_outcome := 'loss';
    b_outcome := 'win';
    return;
  end if;

  if not v_a_pass and not v_b_pass then
    next := 'draw';
    status := 'draw';
    a_outcome := 'draw';
    b_outcome := 'draw';
    return;
  end if;

  -- 둘 다 통과. 여기서부터 우열 답을 본다.
  if (p_a_pick is not null and p_a_pick not in ('a', 'b'))
     or (p_b_pick is not null and p_b_pick not in ('a', 'b')) then
    raise exception '우열 판정 값이 올바르지 않습니다.';
  end if;

  if p_a_pick is null and p_b_pick is null then
    -- 아무도 판정하지 않았다. AI를 부르지 않는다(무임승차 방지).
    next := 'draw';
    status := 'draw';
    a_outcome := 'draw';
    b_outcome := 'draw';
    return;
  end if;

  if p_a_pick is not null and p_b_pick is not null and p_a_pick <> p_b_pick then
    -- 둘 다 "내가 더 잘했다" 또는 둘 다 "상대가 더 잘했다". 아무도 승복하지 않았다.
    next := 'ai';
    return;
  end if;

  -- 합의했거나 한쪽만 답했다. 답한 쪽의 답대로 확정한다.
  v_pick := coalesce(p_a_pick, p_b_pick);
  next := 'finish';
  status := 'finished';
  winner := v_pick;
  -- 품질전 패배에는 감면이 없다.
  a_outcome := case when v_pick = 'a' then 'win' else 'loss' end;
  b_outcome := case when v_pick = 'b' then 'win' else 'loss' end;
end;
$$;

comment on function public.mutual_quality_outcome is
  '품질전 결론(순수 함수). a = creator, b = opponent. 최소 기준 먼저, 둘 다 통과면 우열 답(합의·한쪽 답은 확정, 불일치는 ai, 양쪽 미답은 draw).';

revoke execute on function public.judging_gate(text, boolean, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.min_verdict_effect(boolean, text, boolean) from public, anon, authenticated;
revoke execute on function public.mutual_speed_outcome(text, timestamptz, bigint, text, timestamptz, bigint)
  from public, anon, authenticated;
revoke execute on function public.mutual_quality_outcome(text, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- open_judging_window: 판정 창을 여는 유일한 지점
-- ---------------------------------------------------------------------------
-- judging_opened_at·judge_deadline_at에 값을 넣는 곳은 이 함수 하나다. 그래서 "창 열림 + 24시간"
-- 표현식이 코드에 한 번만 있다. 부르는 곳: accept_submission(양쪽 제출), settle_expired_battles(마감).
create function public.open_judging_window(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.battles
  set status = 'judging',
      judging_opened_at = now(),
      judge_deadline_at = now() + interval '24 hours'
  where id = p_battle_id and status = 'active';

  if not found then
    raise exception '제출 창인 대결만 판정 창을 열 수 있습니다.';
  end if;
end;
$$;

comment on function public.open_judging_window is
  '판정 창을 연다(status judging, 창 열림 시각, 기한 = 열림 + 24시간). 두 컬럼을 쓰는 유일한 함수. 내부 전용.';

revoke execute on function public.open_judging_window(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- resolve_battle 재작성: 판정 사실로 결론을 내고, 결론이 나면 finalize_battle로 적용한다
-- ---------------------------------------------------------------------------
-- 시그니처(uuid -> text)는 그대로다. 반환은 호출 뒤의 대결 상태.
-- judging이 아닌 대결(제출 창·종결)은 건드리지 않는다 — 늦게 온 판정이 종결된 대결의 점수를 다시
-- 건드리지 않고, 제출 창의 정산은 settle_expired_battles가 judging_gate로 따로 본다.
create or replace function public.resolve_battle(p_battle_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_a_sub public.battle_submissions%rowtype;
  v_b_sub public.battle_submissions%rowtype;
  v_a_judgment public.battle_judgments%rowtype;
  v_b_judgment public.battle_judgments%rowtype;
  v_a_effect text;
  v_b_effect text;
  v_speed record;
  v_quality record;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status <> 'judging' or v_battle.opponent_id is null then
    return v_battle.status;
  end if;

  select * into v_a_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.creator_id;

  select * into v_b_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.opponent_id;

  -- a의 판정은 b의 제출에 대한 것이고, b의 판정은 a의 제출에 대한 것이다.
  select * into v_a_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.creator_id;

  select * into v_b_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.opponent_id;

  -- meets_criteria는 승인에도 채워지므로, AI 결과로 넘기는 것은 AI가 정한 값뿐이다.
  v_a_effect := public.min_verdict_effect(
    v_a_sub.id is not null,
    v_b_judgment.min_verdict,
    case when v_a_sub.verdict_source = 'ai' then v_a_sub.meets_criteria end
  );
  v_b_effect := public.min_verdict_effect(
    v_b_sub.id is not null,
    v_a_judgment.min_verdict,
    case when v_b_sub.verdict_source = 'ai' then v_b_sub.meets_criteria end
  );

  -- 판정 대기 또는 AI 재판정 대기. AI 재판정 잡은 3단계에서 여기에 붙는다.
  if v_a_effect = 'pending' or v_b_effect = 'pending' then
    return v_battle.status;
  end if;

  if v_battle.type = 'speed' then
    select * into v_speed
    from public.mutual_speed_outcome(
      v_a_effect, v_a_sub.submitted_at, v_a_sub.id,
      v_b_effect, v_b_sub.submitted_at, v_b_sub.id
    );

    perform public.finalize_battle(
      p_battle_id,
      v_speed.status,
      case v_speed.winner
        when 'a' then v_battle.creator_id
        when 'b' then v_battle.opponent_id
        else null
      end,
      v_speed.a_outcome,
      v_speed.b_outcome
    );

    return v_speed.status;
  end if;

  select * into v_quality
  from public.mutual_quality_outcome(
    v_a_effect,
    v_b_effect,
    case v_a_judgment.superior_id
      when v_battle.creator_id then 'a'
      when v_battle.opponent_id then 'b'
      else null
    end,
    case v_b_judgment.superior_id
      when v_battle.creator_id then 'a'
      when v_battle.opponent_id then 'b'
      else null
    end
  );

  -- 우열 불일치: AI가 가른다. 우열 AI 재판정 잡은 3단계에서 여기에 붙는다.
  if v_quality.next in ('ai', 'wait') then
    return v_battle.status;
  end if;

  perform public.finalize_battle(
    p_battle_id,
    v_quality.status,
    case v_quality.winner
      when 'a' then v_battle.creator_id
      when 'b' then v_battle.opponent_id
      else null
    end,
    v_quality.a_outcome,
    v_quality.b_outcome
  );

  return v_quality.status;
end;
$$;

comment on function public.resolve_battle is
  '판정 창의 판정 사실(승인·불복·우열·AI 결과)로 결론을 내 finalize_battle로 적용. judging이 아니면 그대로 반환. 내부 전용.';

revoke execute on function public.resolve_battle(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- settle_expired_battles 재작성: 마감이 지난 제출 창을 judging_gate대로 정리한다 (cron 1분)
-- ---------------------------------------------------------------------------
-- active만 본다. judging에서 마감(deadline_at)이 지나도 아무 일도 없다 — 판정 창은 judge_deadline_at이
-- 지배한다. 한 대결의 실패가 같은 tick의 다른 대결을 막지 않게 한 바퀴를 예외 블록으로 감싼다.
-- cron 전용이라 auth.uid() 가드를 두지 않는다(cron에는 uid가 없어 가드가 항상 실패한다).
-- 대신 EXECUTE를 authenticated까지 전부 회수한다(기존과 같은 예외).
create or replace function public.settle_expired_battles()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle record;
  v_a_submitted boolean;
  v_b_submitted boolean;
  v_action text;
  v_settled integer := 0;
begin
  for v_battle in
    select b.id, b.type, b.creator_id, b.opponent_id
    from public.battles b
    where b.status = 'active'
      and b.deadline_at is not null
      and b.deadline_at <= now()
      and b.opponent_id is not null
    order by b.deadline_at
    for update skip locked
  loop
    begin
      select exists (
        select 1 from public.battle_submissions
        where battle_id = v_battle.id and user_id = v_battle.creator_id
      ) into v_a_submitted;

      select exists (
        select 1 from public.battle_submissions
        where battle_id = v_battle.id and user_id = v_battle.opponent_id
      ) into v_b_submitted;

      v_action := public.judging_gate(v_battle.type, v_a_submitted, v_b_submitted, true);

      case v_action
        when 'open' then
          perform public.open_judging_window(v_battle.id);
        when 'finish_a' then
          perform public.finalize_battle(v_battle.id, 'finished', v_battle.creator_id, 'win', 'loss');
        when 'finish_b' then
          perform public.finalize_battle(v_battle.id, 'finished', v_battle.opponent_id, 'loss', 'win');
        when 'draw' then
          perform public.finalize_battle(v_battle.id, 'draw', null, 'draw', 'draw');
        else
          raise exception '마감 정산 결과가 올바르지 않습니다: %', v_action;
      end case;

      v_settled := v_settled + 1;
    exception
      when others then
        raise warning 'settle_expired_battles: 대결 % 정리 실패: %', v_battle.id, sqlerrm;
    end;
  end loop;

  return v_settled;
end;
$$;

comment on function public.settle_expired_battles is
  '마감이 지난 제출 창(active)을 정리: 판정 창 열기 / 품질전 한쪽 제출 승리 / 제출 0건 draw. cron 전용.';

revoke execute on function public.settle_expired_battles() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- close_expired_judging_windows: 판정 기한이 지난 창을 닫는다 (cron 1분, 신규)
-- ---------------------------------------------------------------------------
-- 필요한 판정(= 상대가 제출한 쪽의 판정) 중 빠진 것만 승인으로 채우고 결론을 낸다.
-- 결론이 나지 않으면(AI 재판정 대기) 그대로 둔다 — 판정 기한이 진행 중인 AI 재판정을 죽이지 않는다.
-- 다음 tick에서 같은 일이 멱등하게 다시 돈다.
-- cron 전용이라 auth.uid() 가드를 두지 않고 EXECUTE를 authenticated까지 전부 회수한다
-- (settle_expired_battles와 같은 예외).
create function public.close_expired_judging_windows()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle record;
  v_pair record;
  v_status text;
  v_closed integer := 0;
begin
  for v_battle in
    select b.id, b.creator_id, b.opponent_id
    from public.battles b
    where b.status = 'judging'
      and b.judge_deadline_at <= now()
    order by b.judge_deadline_at
    for update skip locked
  loop
    begin
      for v_pair in
        select v_battle.creator_id as judge_id, v_battle.opponent_id as target_id
        union all
        select v_battle.opponent_id, v_battle.creator_id
      loop
        -- 상대가 제출하지 않았으면 판정할 것이 없다.
        continue when not exists (
          select 1 from public.battle_submissions
          where battle_id = v_battle.id and user_id = v_pair.target_id
        );

        insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
        values (v_battle.id, v_pair.judge_id, 'approve', null, true)
        on conflict (battle_id, judge_id) do nothing;

        if found then
          update public.battle_participants
          set has_judged = true
          where battle_id = v_battle.id and user_id = v_pair.judge_id;

          update public.battle_submissions
          set meets_criteria = true,
              verdict_source = 'auto'
          where battle_id = v_battle.id and user_id = v_pair.target_id;
        end if;
      end loop;

      v_status := public.resolve_battle(v_battle.id);

      if v_status <> 'judging' then
        v_closed := v_closed + 1;
      end if;
    exception
      when others then
        raise warning 'close_expired_judging_windows: 대결 % 정리 실패: %', v_battle.id, sqlerrm;
    end;
  end loop;

  return v_closed;
end;
$$;

comment on function public.close_expired_judging_windows is
  '판정 기한이 지난 창에서 빠진 판정을 승인(auto)으로 채우고 결론을 낸다. AI 재판정 대기는 그대로 둔다. cron 전용.';

revoke execute on function public.close_expired_judging_windows() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- submit_judgment: 참가자가 상대 증거를 판정한다 (앱 RPC, 신규)
-- ---------------------------------------------------------------------------
-- 판정 내용(승인/불복, 우열)은 사실로만 기록하고 결론은 resolve_battle이 낸다.
-- 반환: 호출 뒤의 대결 상태. 앱은 이 값으로 승패를 계산하지 않고 상세를 다시 읽는다.
create function public.submit_judgment(
  p_battle_id uuid,
  p_min_verdict text,
  p_superior_id uuid
)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_battle public.battles%rowtype;
  v_target_id uuid;
  v_target public.battle_submissions%rowtype;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  -- null에 안전한 형태(`not in`은 비로그인일 때 통과한다).
  if v_me is distinct from v_battle.creator_id
     and v_me is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if v_battle.status <> 'judging' then
    raise exception using message = '판정할 수 있는 상태가 아닙니다.', hint = 'JUDGING_NOT_OPEN';
  end if;

  if v_battle.judge_deadline_at <= now() then
    raise exception using message = '판정 기한이 지났습니다.', hint = 'JUDGE_WINDOW_CLOSED';
  end if;

  if p_min_verdict is null or p_min_verdict not in ('approve', 'reject') then
    raise exception '판정 값이 올바르지 않습니다.';
  end if;

  v_target_id := case when v_me = v_battle.creator_id then v_battle.opponent_id else v_battle.creator_id end;

  select * into v_target from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_target_id;

  if v_target.id is null then
    raise exception using message = '상대가 제출하지 않아 판정할 것이 없습니다.', hint = 'NOTHING_TO_JUDGE';
  end if;

  perform 1 from public.battle_judgments where battle_id = p_battle_id and judge_id = v_me;
  if found then
    raise exception using message = '이미 판정했습니다.', hint = 'ALREADY_JUDGED';
  end if;

  -- 유형과 참가자가 다른 테이블에 있어 CHECK로 쓸 수 없는 규칙.
  if v_battle.type = 'speed' then
    if p_superior_id is not null then
      raise exception '속도전에는 우열 판정이 없습니다.';
    end if;
  else
    -- 품질전은 최소 기준과 우열을 한 번에 답한다(design 결정 사항 2).
    if p_superior_id is null then
      raise exception using message = '우열 판정이 필요합니다.', hint = 'SUPERIORITY_REQUIRED';
    end if;
    if p_superior_id is distinct from v_battle.creator_id
       and p_superior_id is distinct from v_battle.opponent_id then
      raise exception '우열 판정 대상이 이 대결의 참가자가 아닙니다.';
    end if;
  end if;

  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  values (p_battle_id, v_me, p_min_verdict, p_superior_id, false);

  update public.battle_participants
  set has_judged = true
  where battle_id = p_battle_id and user_id = v_me;

  if p_min_verdict = 'approve' then
    update public.battle_submissions
    set meets_criteria = true,
        verdict_source = 'opponent'
    where id = v_target.id;
  end if;
  -- reject: 상대 제출은 AI가 다시 본다. AI 재판정 잡은 3단계에서 여기에 붙는다.

  return public.resolve_battle(p_battle_id);
end;
$$;

comment on function public.submit_judgment is
  '판정 창에서 상대 증거를 판정한다(한 번뿐). 속도전은 승인/불복, 품질전은 승인/불복 + 우열. 결론은 resolve_battle이 낸다.';

revoke execute on function public.submit_judgment(uuid, text, uuid) from public, anon;
grant execute on function public.submit_judgment(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- accept_submission 재정의: 교체와 판정 창 열기 (시그니처 유지)
-- ---------------------------------------------------------------------------
-- 인자 시그니처를 그대로 둔 create or replace다. 시그니처가 달라지면 새 오버로드가 생겨 배포된
-- submit-evidence가 옛 함수를 계속 부른다(ai-judge 6단계 함정). GRANT도 그대로 남는다.
--
-- battles 행 잠금이 직렬화 지점이다. 내 교체와 상대의 첫 제출이 동시에 오면 둘 다 이 잠금을 기다리고,
-- 상대가 먼저 커밋하면 내 교체는 judging을 보고 거부된다. 교체된 사진과 잠긴 사진이 섞이지 않는다.
create or replace function public.accept_submission(
  p_user_id uuid,
  p_battle_id uuid,
  p_object_path text,
  p_captured_at timestamptz
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_now timestamptz := now();
  v_opponent_id uuid;
  v_mine public.battle_submissions%rowtype;
  v_opponent_submitted boolean;
  v_submission public.battle_submissions%rowtype;
  v_replaced_path text;
  v_judging_opened boolean := false;
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  if p_object_path is null or length(btrim(p_object_path)) = 0 then
    raise exception '사진 경로가 필요합니다.';
  end if;

  if p_captured_at is null then
    raise exception '촬영 시각이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  -- null에 안전한 형태. 비로그인(=null)이 통과하던 `not in` 함정을 피한다.
  if p_user_id is distinct from v_battle.creator_id
     and p_user_id is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  -- 참가할 때 확인했지만 그 사이 철회했을 수 있다. 불복되면 이 사진이 AI로 나간다.
  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  -- 판정 창이 열렸거나(상대도 제출했다) 종결됐으면 더 낼 수도 바꿀 수도 없다.
  -- 마감만 지난 경우는 아래에서 따로 구분해 알린다.
  if v_battle.status <> 'active' then
    raise exception using message = '제출할 수 있는 상태가 아닙니다.', hint = 'SUBMISSION_LOCKED';
  end if;

  if v_battle.deadline_at is null or v_battle.deadline_at <= v_now then
    raise exception using message = '마감이 지났습니다.', hint = 'DEADLINE_PASSED';
  end if;

  -- 경로 위조 차단. Storage 정책과 같은 규칙을 서버에서 한 번 더 본다.
  if p_object_path not like (p_battle_id::text || '/' || p_user_id::text || '/%') then
    raise exception '사진 경로가 올바르지 않습니다.';
  end if;

  -- 대결이 시작되기 전에 찍어 둔 사진은 이 대결의 증거가 아니다.
  if v_battle.started_at is not null and p_captured_at < v_battle.started_at then
    raise exception using message = '대결 시작 전에 찍은 사진입니다.', hint = 'CAPTURED_BEFORE_START';
  end if;

  -- 촬영과 수신이 10분 이상 벌어지면 거부한다. 기기 시계가 앞선 경우도 같으므로 절댓값으로 본다.
  if abs(extract(epoch from (v_now - p_captured_at))) >= 600 then
    raise exception using message = '촬영 시각과 수신 시각이 너무 벌어졌습니다.', hint = 'CAPTURE_TIME_MISMATCH';
  end if;

  v_opponent_id := case
    when p_user_id = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  select * into v_mine from public.battle_submissions
  where battle_id = p_battle_id and user_id = p_user_id;

  select exists (
    select 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = v_opponent_id
  ) into v_opponent_submitted;

  if v_mine.id is not null then
    -- 품질전에는 교체가 없다.
    if v_battle.type = 'quality' then
      raise exception using message = '이미 제출했습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    -- 상대가 제출하는 순간 내 사진도 잠긴다. 그 순간 판정 창이 열리므로 위 status 검사에서 먼저 걸리지만,
    -- 규칙의 근거를 이 자리에 둔다.
    if v_opponent_submitted then
      raise exception using message = '상대가 이미 제출해서 바꿀 수 없습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    -- 교체: 행을 덮어쓰고 제출 시각을 다시 찍는다. 옛 사진 경로는 Edge가 지우도록 돌려준다.
    v_replaced_path := nullif(v_mine.object_path, p_object_path);

    update public.battle_submissions
    set object_path = p_object_path,
        captured_at = p_captured_at,
        submitted_at = v_now
    where id = v_mine.id
    returning * into v_submission;
  else
    insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
    values (p_battle_id, p_user_id, p_object_path, p_captured_at, v_now)
    returning * into v_submission;

    -- "상대가 제출했어요"를 알리는 요약. 시각을 담지 않으므로 교체해도 값이 바뀌지 않는다.
    update public.battle_participants
    set has_submitted = true
    where battle_id = p_battle_id and user_id = p_user_id;

    -- 양쪽 제출: 마감을 기다리지 않고 같은 트랜잭션에서 판정 창을 연다.
    if public.judging_gate(v_battle.type, true, v_opponent_submitted, false) = 'open' then
      perform public.open_judging_window(p_battle_id);
      v_judging_opened := true;
    end if;
  end if;

  return jsonb_build_object(
    'submission_id', v_submission.id,
    'type', v_battle.type,
    'replaced_object_path', v_replaced_path,
    'judging_opened', v_judging_opened,
    'battle_status', case when v_judging_opened then 'judging' else v_battle.status end
  );
end;
$$;

comment on function public.accept_submission is
  '증거 사진 제출 수락(서버 전용). 거부는 행을 만들지 않는다. 속도전은 상대 미제출 동안 교체(덮어쓰기, submitted_at 갱신)할 수 있고, 양쪽이 제출하면 판정 창을 연다.';

-- ---------------------------------------------------------------------------
-- 제출 즉시 판정의 잔재 제거
-- ---------------------------------------------------------------------------
-- record_speed_verdict: 제출 즉시 AI 판정이 사라진다. 배포된 submit-evidence가 이 함수를 부르므로
-- 적용 직후 재배포가 필요하다.
-- sweep_stale_submissions: 끊긴 동기 판정이 없다. ai_criteria_calls 정리 몫만 아래 함수로 옮긴다.
drop function public.record_speed_verdict(bigint, text, text, text);
drop function public.sweep_stale_submissions();

-- 2분 넘게 in_progress인 기준 생성 호출을 failed로 정리한다. cron 전용이라 auth.uid() 가드를 두지 않고
-- (cron에는 uid가 없어 가드가 항상 실패한다) EXECUTE를 authenticated까지 전부 회수한다.
create function public.sweep_stale_criteria_calls()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_swept integer;
begin
  update public.ai_criteria_calls
  set status = 'failed'
  where status = 'in_progress'
    and created_at <= now() - interval '2 minutes';

  get diagnostics v_swept = row_count;
  return v_swept;
end;
$$;

comment on function public.sweep_stale_criteria_calls is
  '2분 넘게 in_progress인 기준 생성 호출을 failed로 정리한다. cron 전용.';

revoke execute on function public.sweep_stale_criteria_calls() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Storage(battle_evidence) 정책 교체
-- ---------------------------------------------------------------------------
-- createSignedUrl도 select 정책을 거치므로, 판정 창 전에는 상대 사진의 서명 URL 발급 자체가 실패한다.
drop policy "users can read own evidence or finished battle evidence" on storage.objects;
drop policy "participants can upload evidence to own folder" on storage.objects;

-- 조회: 내 사진은 언제든, 상대 사진은 판정 창이 열린 뒤 또는 종결 뒤.
create policy "users can read own evidence or revealed battle evidence"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or exists (
        select 1 from public.battles b
        where b.id::text = (storage.foldername(name))[1]
          and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
          and (b.judging_opened_at is not null
               or b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed'))
      )
    )
  );

-- 업로드: 본인 폴더에, 제출 창인 내 대결에만. status = 'active'가 이미 창이 열리지 않았음을 뜻하지만,
-- 교체 업로드가 창이 열린 뒤에 끼어들지 못하게 두 번 본다.
create policy "participants can upload evidence to own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.battles b
      where b.id::text = (storage.foldername(name))[1]
        and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
        and b.status = 'active'
        and b.deadline_at > now()
        and b.judging_opened_at is null
    )
  );

-- update 정책은 두지 않는다(덮어쓰기 금지 유지). 교체는 새 파일 업로드 + 옛 파일 삭제다.
-- delete 정책("participants can delete own evidence")은 그대로 둔다.

-- ---------------------------------------------------------------------------
-- cron
-- ---------------------------------------------------------------------------
-- 세 작업을 합치지 않는다. 한 작업의 명령 문자열은 한 트랜잭션이라, 판정 창 닫기에서 예외가 나면
-- 같은 tick의 마감 정산까지 되돌아간다. settle-expired-battles는 1단계에서 이미 1분이고 함수 이름이
-- 같아 다시 등록하지 않는다.
select cron.schedule(
  'close-judging-windows',
  '* * * * *',
  $$select public.close_expired_judging_windows()$$
);

-- 같은 이름으로 다시 부르면 기존 작업이 갱신된다. sweep_stale_submissions·dispatch_quality_judgments를
-- 뺀다(품질전 잡을 만드는 곳이 없어졌다). 3단계가 dispatch_ai_judgments를 여기에 더한다.
select cron.schedule(
  'ai-judge-tick',
  '* * * * *',
  $$select public.sweep_stale_criteria_calls()$$
);
