-- ai-judge 1단계: 판정 규칙 순수 함수.
--
-- 근거: docs/specs/ai-judge/design.md "판정 규칙 순수 함수", 속도전 R/D 규칙, 품질전 Q4/Q8/Q9 규칙.
-- 부작용 없는 immutable 함수로 분리해, 상태를 바꾸는 함수(resolve_battle, 6단계 record_quality_verdict)가
-- 같은 규칙을 공유하고 supabase/tests/battle_outcome_rules.sql이 표로 검증한다.
-- 참가자 a/b는 호출부에서 a = creator, b = opponent로 고정 매핑한다.
--
-- 이 함수들은 데이터를 읽지 않지만 앱이 부를 이유도 없으므로 EXECUTE를 전부 회수한다.
-- (SECURITY DEFINER가 아니므로 로그인 가드 규칙 대상이 아니다.)

-- 속도전 결과.
--   decision: 'continue'(아직 종결 아님) | 'finish'(승자 있음) | 'draw'
--   winner: 'a' | 'b' | null
--   *_outcome: win | completed_loss | loss | draw | null(continue)
--
-- 입력
--   *_passed_at / *_pass_seq: 통과한 제출의 서버 시각과 battle_submissions.id (없으면 null)
--   *_attempts: passed + failed 수(error 미산입)
--   *_judging: 판정 중인 제출이 있는지
--   p_deadline_passed: 마감이 지났는지
create function public.speed_outcome(
  p_a_passed_at timestamptz,
  p_a_pass_seq bigint,
  p_a_attempts integer,
  p_a_judging boolean,
  p_b_passed_at timestamptz,
  p_b_pass_seq bigint,
  p_b_attempts integer,
  p_b_judging boolean,
  p_deadline_passed boolean,
  out decision text,
  out winner text,
  out a_outcome text,
  out b_outcome text
)
language plpgsql
immutable
set search_path = public
as $$
declare
  -- 참가자당 대결마다 AI 판정 최대 5회(spec 결정 37).
  c_max_attempts constant integer := 5;
  v_a_passed boolean := p_a_passed_at is not null;
  v_b_passed boolean := p_b_passed_at is not null;
  v_a_exhausted boolean := coalesce(p_a_attempts, 0) >= c_max_attempts;
  v_b_exhausted boolean := coalesce(p_b_attempts, 0) >= c_max_attempts;
begin
  -- 판정 중인 제출은 결과를 바꿀 수 있다(더 이른 시각의 제출이 통과하면 역전).
  -- 그래서 마감 전이든 후든 판정 중인 제출이 있으면 기다린다(결정 50).
  if coalesce(p_a_judging, false) or coalesce(p_b_judging, false) then
    decision := 'continue';
    return;
  end if;

  -- R1: 양쪽 통과 -> 통과 시각이 이른 쪽, 동률이면 먼저 기록된 제출(seq가 작은 쪽).
  -- 마감 뒤에 도달해도 같은 규칙이다(D 규칙의 방어적 처리).
  if v_a_passed and v_b_passed then
    decision := 'finish';
    if p_a_passed_at < p_b_passed_at
       or (p_a_passed_at = p_b_passed_at and p_a_pass_seq < p_b_pass_seq) then
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

  -- R2: 한쪽 통과 + 상대 판정 소진 -> 더 이상 바뀔 수 없으므로 즉시 종결(결정 62).
  -- D: 마감이 지났으면 한쪽 통과만으로 종결.
  if v_a_passed and (v_b_exhausted or coalesce(p_deadline_passed, false)) then
    decision := 'finish';
    winner := 'a';
    a_outcome := 'win';
    b_outcome := 'loss';
    return;
  end if;

  if v_b_passed and (v_a_exhausted or coalesce(p_deadline_passed, false)) then
    decision := 'finish';
    winner := 'b';
    a_outcome := 'loss';
    b_outcome := 'win';
    return;
  end if;

  -- R3: 통과자 없이 양쪽 소진 -> 즉시 무승부. D: 통과자 없이 마감 -> 무승부.
  if not v_a_passed and not v_b_passed
     and ((v_a_exhausted and v_b_exhausted) or coalesce(p_deadline_passed, false)) then
    decision := 'draw';
    a_outcome := 'draw';
    b_outcome := 'draw';
    return;
  end if;

  decision := 'continue';
end;
$$;

comment on function public.speed_outcome is
  '속도전 결과 규칙(순수 함수). a = creator, b = opponent. 판정 중 제출이 있으면 continue.';

-- 품질전 AI 판정 결과(Q4).
--   valid=false: 둘 다 최소 기준을 충족했는데 AI가 승자를 'a'/'b'로 고르지 않음 -> 실패로 보고 재시도.
--   status: 'finished' | 'draw'
create function public.quality_outcome(
  p_a_meets boolean,
  p_b_meets boolean,
  p_ai_winner text,
  out valid boolean,
  out status text,
  out winner text,
  out a_outcome text,
  out b_outcome text
)
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_a_meets is null or p_b_meets is null then
    valid := false;
    return;
  end if;

  if p_a_meets and p_b_meets then
    -- 동점 없음(결정 54). 승자가 비었거나 형식이 틀리면 성공으로 치지 않는다.
    if p_ai_winner is distinct from 'a' and p_ai_winner is distinct from 'b' then
      valid := false;
      return;
    end if;
    valid := true;
    status := 'finished';
    winner := p_ai_winner;
    a_outcome := case when p_ai_winner = 'a' then 'win' else 'loss' end;
    b_outcome := case when p_ai_winner = 'b' then 'win' else 'loss' end;
    return;
  end if;

  valid := true;

  -- 한쪽만 충족 -> 충족한 쪽 승리. 이때 AI의 winner 값은 무시한다.
  if p_a_meets then
    status := 'finished';
    winner := 'a';
    a_outcome := 'win';
    b_outcome := 'loss';
  elsif p_b_meets then
    status := 'finished';
    winner := 'b';
    a_outcome := 'loss';
    b_outcome := 'win';
  else
    status := 'draw';
    a_outcome := 'draw';
    b_outcome := 'draw';
  end if;
end;
$$;

comment on function public.quality_outcome is
  '품질전 AI 판정 결과 규칙(순수 함수). 둘 다 충족인데 승자가 없으면 valid=false(재시도 대상).';

-- 품질전 마감 결과(Q8/Q9). 판정이 시작되지 않은(active) 대결에만 쓴다.
-- 양쪽 제출이면 이미 judging이어야 하므로 여기서 결정하지 않고 전부 null을 돌려준다.
create function public.quality_deadline_outcome(
  p_a_submitted boolean,
  p_b_submitted boolean,
  out status text,
  out winner text,
  out a_outcome text,
  out b_outcome text
)
language plpgsql
immutable
set search_path = public
as $$
begin
  if coalesce(p_a_submitted, false) and coalesce(p_b_submitted, false) then
    return;
  end if;

  -- 한쪽만 제출 -> AI 판정 없이 제출한 쪽 승리(결정 15·59). 품질전 패배는 감면 없이 loss.
  if coalesce(p_a_submitted, false) then
    status := 'finished';
    winner := 'a';
    a_outcome := 'win';
    b_outcome := 'loss';
  elsif coalesce(p_b_submitted, false) then
    status := 'finished';
    winner := 'b';
    a_outcome := 'loss';
    b_outcome := 'win';
  else
    status := 'draw';
    a_outcome := 'draw';
    b_outcome := 'draw';
  end if;
end;
$$;

comment on function public.quality_deadline_outcome is
  '품질전 마감 결과 규칙(순수 함수). 양쪽 제출이면 결정하지 않고 null.';

-- 결과별 점수 변화(결정 38·39). 하한 0은 finalize_battle이 적용한다.
create function public.outcome_score_delta(p_outcome text)
returns integer
language plpgsql
immutable
set search_path = public
as $$
begin
  return case p_outcome
    when 'win' then 3
    when 'completed_loss' then -1
    when 'loss' then -3
    when 'forfeit' then -3
    when 'draw' then -1
    else null
  end;
end;
$$;

comment on function public.outcome_score_delta is
  'outcome -> 점수 변화. win +3, completed_loss -1, loss/forfeit -3, draw -1. 그 외 null.';

revoke execute on function public.speed_outcome(timestamptz, bigint, integer, boolean, timestamptz, bigint, integer, boolean, boolean)
  from public, anon, authenticated;
revoke execute on function public.quality_outcome(boolean, boolean, text) from public, anon, authenticated;
revoke execute on function public.quality_deadline_outcome(boolean, boolean) from public, anon, authenticated;
revoke execute on function public.outcome_score_delta(text) from public, anon, authenticated;
