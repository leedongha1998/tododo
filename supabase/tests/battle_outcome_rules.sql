-- 판정 규칙 순수 함수 테이블 테스트 (mutual-judge design.md "규칙 테스트 필수 케이스" + 점수 5케이스).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/battle_outcome_rules.sql
--
-- SELECT만 한다(쓰기 없음). 결과는 케이스마다 한 행이고 ok 열이 전부 true여야 한다.
-- 마지막 행(case_no 99)은 전체 요약이다.
--
-- 표기 (a = creator, b = opponent, 없음은 -)
--   judging_gate:           action
--   min_verdict_effect:     none | pending | pass | fail
--   mutual_speed_outcome:   status/winner/a_outcome/b_outcome
--   mutual_quality_outcome: next/status/winner/a_outcome/b_outcome
with
t as (
  select
    timestamptz '2026-09-15 10:00:00+09' as t1,
    timestamptz '2026-09-15 11:00:00+09' as t2
),
gate_cases (case_no, description, expected, type, a_submitted, b_submitted, deadline_passed) as (
  values
    (1, '양쪽 제출, 마감 전(속도전) - 마감을 기다리지 않는다', 'open', 'speed', true, true, false),
    (2, '양쪽 제출, 마감 전(품질전)', 'open', 'quality', true, true, false),
    (3, '한쪽 제출, 마감 전 - 제출 창 유지', 'wait', 'speed', true, false, false),
    (4, '제출 없음, 마감 전', 'wait', 'quality', false, false, false),
    (5, '속도전 a만 제출, 마감 후 - 판정 창(판정자는 b)', 'open', 'speed', true, false, true),
    (6, '속도전 b만 제출, 마감 후', 'open', 'speed', false, true, true),
    (7, '속도전 제출 없음, 마감 후', 'draw', 'speed', false, false, true),
    (8, '품질전 a만 제출, 마감 후 - 판정 없이 a 승리', 'finish_a', 'quality', true, false, true),
    (9, '품질전 b만 제출, 마감 후', 'finish_b', 'quality', false, true, true),
    (10, '품질전 제출 없음, 마감 후', 'draw', 'quality', false, false, true),
    (11, '양쪽 제출, 마감 후', 'open', 'speed', true, true, true)
),
effect_cases (case_no, description, expected, submitted, opponent_verdict, ai_meets) as (
  values
    (12, '제출 없음', 'none', false, null::text, null::boolean),
    (13, '제출했고 상대가 아직 판정 안 함', 'pending', true, null, null),
    (14, '상대 승인(사람 또는 자동)', 'pass', true, 'approve', null),
    (15, '상대 불복, AI 결과 없음', 'pending', true, 'reject', null),
    (16, '상대 불복, AI 통과 - AI가 사람 판정을 대체한다', 'pass', true, 'reject', true),
    (17, '상대 불복, AI 미달', 'fail', true, 'reject', false),
    (18, '상대 승인이면 AI 값은 보지 않는다', 'pass', true, 'approve', false)
),
speed_cases (case_no, description, expected, a_effect, a_at, a_seq, b_effect, b_at, b_seq) as (
  select 19, '속도전 양쪽 유효, a가 먼저', 'finished/a/win/completed_loss',
         'pass', t1, 1::bigint, 'pass', t2, 2::bigint from t
  union all
  select 20, '속도전 양쪽 유효, b가 먼저', 'finished/b/completed_loss/win',
         'pass', t2, 2, 'pass', t1, 1 from t
  union all
  select 21, '속도전 같은 시각, id a < b', 'finished/a/win/completed_loss',
         'pass', t1, 1, 'pass', t1, 2 from t
  union all
  select 22, '속도전 a 유효, b 미달', 'finished/a/win/loss',
         'pass', t1, 1, 'fail', t2, 2 from t
  union all
  select 23, '속도전 a 유효, b 미제출', 'finished/a/win/loss',
         'pass', t1, 1, 'none', null, null from t
  union all
  select 24, '속도전 a 미달, b 유효', 'finished/b/loss/win',
         'fail', t1, 1, 'pass', t2, 2 from t
  union all
  select 25, '속도전 양쪽 미달', 'draw/-/draw/draw',
         'fail', t1, 1, 'fail', t2, 2 from t
  union all
  select 26, '속도전 a 미달, b 미제출', 'draw/-/draw/draw',
         'fail', t1, 1, 'none', null, null from t
  union all
  select 27, '속도전 양쪽 미제출(창이 열리지 않는 경우의 방어적 처리)', 'draw/-/draw/draw',
         'none', null, null, 'none', null, null from t
  union all
  select 28, '속도전 미결이 있으면 결정하지 않는다', '-/-/-/-',
         'pending', t1, 1, 'pass', t2, 2 from t
),
quality_cases (case_no, description, expected, a_effect, b_effect, a_pick, b_pick) as (
  values
    (29, '품질전 a만 통과 - 우열을 묻지 않는다', 'finish/finished/a/win/loss', 'pass', 'fail', 'b', 'b'),
    (30, '품질전 b만 통과', 'finish/finished/b/loss/win', 'fail', 'pass', 'a', 'a'),
    (31, '품질전 둘 다 미달', 'draw/draw/-/draw/draw', 'fail', 'fail', 'a', 'b'),
    (32, '품질전 합의: 둘 다 a', 'finish/finished/a/win/loss', 'pass', 'pass', 'a', 'a'),
    (33, '품질전 합의: 둘 다 b', 'finish/finished/b/loss/win', 'pass', 'pass', 'b', 'b'),
    (34, '품질전 a만 답함(a)', 'finish/finished/a/win/loss', 'pass', 'pass', 'a', null),
    (35, '품질전 b만 답함(b)', 'finish/finished/b/loss/win', 'pass', 'pass', null, 'b'),
    (36, '품질전 불일치: 둘 다 자기 승리 주장', 'ai/-/-/-/-', 'pass', 'pass', 'a', 'b'),
    (37, '품질전 불일치: 둘 다 상대 승리 주장', 'ai/-/-/-/-', 'pass', 'pass', 'b', 'a'),
    (38, '품질전 양쪽 미답 - AI 없이 무승부', 'draw/draw/-/draw/draw', 'pass', 'pass', null, null),
    (39, '품질전 최소 기준 미결이면 기다린다', 'wait/-/-/-/-', 'pending', 'pass', 'a', 'a'),
    (40, '품질전 a 통과, b 미제출(방어적 처리)', 'finish/finished/a/win/loss', 'pass', 'none', null, null)
),
score_cases (case_no, description, expected, outcome) as (
  values
    (41, '점수 win', '3', 'win'),
    (42, '점수 completed_loss', '-1', 'completed_loss'),
    (43, '점수 loss', '-3', 'loss'),
    (44, '점수 forfeit', '-3', 'forfeit'),
    (45, '점수 draw', '-1', 'draw')
),
results as (
  select c.case_no, c.description, c.expected,
         public.judging_gate(c.type, c.a_submitted, c.b_submitted, c.deadline_passed) as actual
  from gate_cases c
  union all
  select c.case_no, c.description, c.expected,
         public.min_verdict_effect(c.submitted, c.opponent_verdict, c.ai_meets)
  from effect_cases c
  union all
  select c.case_no, c.description, c.expected,
         concat_ws('/', coalesce(o.status, '-'), coalesce(o.winner, '-'),
                   coalesce(o.a_outcome, '-'), coalesce(o.b_outcome, '-'))
  from speed_cases c,
       public.mutual_speed_outcome(c.a_effect, c.a_at, c.a_seq, c.b_effect, c.b_at, c.b_seq) o
  union all
  select c.case_no, c.description, c.expected,
         concat_ws('/', coalesce(o.next, '-'), coalesce(o.status, '-'), coalesce(o.winner, '-'),
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
