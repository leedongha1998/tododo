-- 판정 규칙 순수 함수 테이블 테스트 (mutual-judge design.md "규칙 테스트 필수 케이스").
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/mutual_judge_rules.sql
--
-- SELECT만 한다(쓰기 없음). 결과는 케이스마다 한 행이고 ok 열이 전부 true여야 한다.
-- 마지막 행(case_no 99)은 전체 요약이다.
--
-- battle_outcome_rules.sql을 대체한다 — 그 파일이 테스트하던 speed_outcome·quality_outcome·
-- quality_deadline_outcome은 mutual-judge 2단계에서 drop됐다.
with
t as (
  select
    timestamptz '2026-09-15 10:00:00+09' as t1,
    timestamptz '2026-09-15 11:00:00+09' as t2
),
gate_cases (case_no, description, expected, type, a_submitted, b_submitted, deadline_passed) as (
  select 1, '양쪽 제출, 마감 전 -> 즉시 open', 'open', 'speed', true, true, false
  union all
  select 2, '양쪽 제출, 마감 후에도 open', 'open', 'quality', true, true, true
  union all
  select 3, '한쪽만 제출, 마감 전 -> wait', 'wait', 'speed', true, false, false
  union all
  select 4, '아무도 제출 안 함, 마감 전 -> wait', 'wait', 'quality', false, false, false
  union all
  select 5, '속도전 a만 제출, 마감 후 -> open(판정할 사람이 있다)', 'open', 'speed', true, false, true
  union all
  select 6, '속도전 b만 제출, 마감 후 -> open', 'open', 'speed', false, true, true
  union all
  select 7, '속도전 아무도 제출 안 함, 마감 후 -> draw', 'draw', 'speed', false, false, true
  union all
  select 8, '품질전 a만 제출, 마감 후 -> finish_a(판정 없이 제출자 승리)', 'finish_a', 'quality', true, false, true
  union all
  select 9, '품질전 b만 제출, 마감 후 -> finish_b', 'finish_b', 'quality', false, true, true
  union all
  select 10, '품질전 아무도 제출 안 함, 마감 후 -> draw', 'draw', 'quality', false, false, true
),
verdict_effect_cases (case_no, description, expected, submitted, opponent_verdict, ai_meets) as (
  select 11, '제출 안 함 -> none', 'none', false, null, null
  union all
  select 12, '제출했고 상대가 아직 판정 안 함 -> pending', 'pending', true, null, null
  union all
  select 13, '상대가 승인 -> pass(AI 결과 무관)', 'pass', true, 'approve', null
  union all
  select 14, '상대가 불복, AI 결과 아직 없음 -> pending', 'pending', true, 'reject', null
  union all
  select 15, '상대가 불복, AI가 통과라고 함 -> pass(거짓 불복 뒤집힘)', 'pass', true, 'reject', true
  union all
  select 16, '상대가 불복, AI가 미달이라고 함 -> fail', 'fail', true, 'reject', false
),
speed_cases (case_no, description, expected, a_effect, a_at, a_seq, b_effect, b_at, b_seq) as (
  select 17, '양쪽 pass, a가 먼저', 'finished/a/win/completed_loss',
         'pass', t1, 1::bigint, 'pass', t2, 2::bigint from t
  union all
  select 18, '양쪽 pass, b가 먼저', 'finished/b/completed_loss/win',
         'pass', t2, 2, 'pass', t1, 1 from t
  union all
  select 19, '양쪽 pass, 동시각 -> seq가 작은 쪽(a)', 'finished/a/win/completed_loss',
         'pass', t1, 1, 'pass', t1, 2 from t
  union all
  select 20, 'a pass, b fail', 'finished/a/win/loss', 'pass', t1, 1, 'fail', t1, 2 from t
  union all
  select 21, 'a pass, b none', 'finished/a/win/loss', 'pass', t1, 1, 'none', t1, 2 from t
  union all
  select 22, '양쪽 fail -> draw', 'draw/-/draw/draw', 'fail', t1, 1, 'fail', t1, 2 from t
  union all
  select 23, 'a fail, b none -> draw', 'draw/-/draw/draw', 'fail', t1, 1, 'none', t1, 2 from t
  union all
  select 24, '양쪽 none -> draw(창이 열리지 않는 경우의 방어적 처리)', 'draw/-/draw/draw',
         'none', t1, 1, 'none', t1, 2 from t
),
quality_cases (case_no, description, expected, a_effect, b_effect, a_pick, b_pick) as (
  select 25, 'a pass, b fail -> a 승, 우열 안 묻음', 'finish/finished/a/win/loss', 'pass', 'fail', null, null
  union all
  select 26, 'a fail, b pass -> b 승', 'finish/finished/b/loss/win', 'fail', 'pass', null, null
  union all
  select 27, '둘 다 fail -> draw', 'draw/draw/-/draw/draw', 'fail', 'fail', null, null
  union all
  select 28, '둘 다 pass, 같은 사람(a)을 가리킴 -> 합의, a 승', 'finish/finished/a/win/loss',
         'pass', 'pass', 'a', 'a'
  union all
  select 29, '둘 다 pass, 같은 사람(b)을 가리킴 -> 합의, b 승', 'finish/finished/b/loss/win',
         'pass', 'pass', 'b', 'b'
  union all
  select 30, '둘 다 pass, a만 답함(a) -> a 승', 'finish/finished/a/win/loss',
         'pass', 'pass', 'a', null
  union all
  select 31, '둘 다 pass, b만 답함(b) -> b 승', 'finish/finished/b/loss/win',
         'pass', 'pass', null, 'b'
  union all
  select 32, '둘 다 pass, 둘 다 자기 승리 주장(어긋남) -> AI', 'ai/judging/-/-/-',
         'pass', 'pass', 'a', 'b'
  union all
  select 33, '둘 다 pass, 둘 다 상대 승리 주장(어긋남) -> AI', 'ai/judging/-/-/-',
         'pass', 'pass', 'b', 'a'
  union all
  select 34, '둘 다 pass, 양쪽 다 미답 -> draw(AI 호출 없음)', 'draw/draw/-/draw/draw',
         'pass', 'pass', null, null
),
score_cases (case_no, description, expected, outcome) as (
  select 35, '점수 win', '3', 'win'
  union all
  select 36, '점수 completed_loss', '-1', 'completed_loss'
  union all
  select 37, '점수 loss', '-3', 'loss'
  union all
  select 38, '점수 forfeit', '-3', 'forfeit'
  union all
  select 39, '점수 draw', '-1', 'draw'
),
results as (
  -- judging_gate·min_verdict_effect는 OUT 파라미터가 하나뿐이라 스칼라 함수로 동작한다
  -- (OUT 여러 개인 mutual_speed_outcome·mutual_quality_outcome만 FROM 절의 테이블 함수로 쓴다).
  select c.case_no, c.description, c.expected,
         public.judging_gate(c.type, c.a_submitted, c.b_submitted, c.deadline_passed) as actual
  from gate_cases c
  union all
  select c.case_no, c.description, c.expected,
         public.min_verdict_effect(c.submitted, c.opponent_verdict, c.ai_meets)
  from verdict_effect_cases c
  union all
  select c.case_no, c.description, c.expected,
         concat_ws('/', o.status, coalesce(o.winner, '-'),
                   coalesce(o.a_outcome, '-'), coalesce(o.b_outcome, '-'))
  from speed_cases c,
       public.mutual_speed_outcome(c.a_effect, c.a_at, c.a_seq, c.b_effect, c.b_at, c.b_seq) o
  union all
  select c.case_no, c.description, c.expected,
         concat_ws('/', o.next, coalesce(o.status, '-'), coalesce(o.winner, '-'),
                   coalesce(o.a_outcome, '-'), coalesce(o.b_outcome, '-'))
  from quality_cases c,
       public.mutual_quality_outcome(c.a_effect, c.b_effect, c.a_pick, c.b_pick) o
  union all
  select c.case_no, c.description, c.expected,
         coalesce(public.outcome_score_delta(c.outcome)::text, 'null')
  from score_cases c
)
select case_no, description, expected, actual, expected = actual as ok
from results
union all
select 99, '전체', count(*)::text || '케이스', count(*) filter (where expected = actual)::text || ' 통과',
       bool_and(expected = actual)
from results
order by case_no;
