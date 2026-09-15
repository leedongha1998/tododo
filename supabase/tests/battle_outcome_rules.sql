-- 판정 규칙 순수 함수 테이블 테스트 (ai-judge design.md "필수 규칙 테스트 케이스" 1~18 + 점수 5케이스).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/battle_outcome_rules.sql
--
-- SELECT만 한다(쓰기 없음). 결과는 케이스마다 한 행이고 ok 열이 전부 true여야 한다.
-- 마지막 행(case_no 99)은 전체 요약이다.
--
-- 표기
--   속도전: decision/winner/a_outcome/b_outcome  (a = creator, b = opponent, 없음은 -)
--   품질전 판정: valid/status/winner/a_outcome/b_outcome
--   품질전 마감: status/winner/a_outcome/b_outcome
with
t as (
  select
    timestamptz '2026-09-15 10:00:00+09' as t1,
    timestamptz '2026-09-15 11:00:00+09' as t2
),
speed_cases (
  case_no, description, expected,
  a_passed_at, a_pass_seq, a_attempts, a_judging,
  b_passed_at, b_pass_seq, b_attempts, b_judging,
  deadline_passed
) as (
  select 1, '속도전 양쪽 통과, a가 먼저', 'finish/a/win/completed_loss',
         t1, 1::bigint, 1, false, t2, 2::bigint, 1, false, false from t
  union all
  select 2, '속도전 양쪽 통과, b가 먼저', 'finish/b/completed_loss/win',
         t2, 2, 1, false, t1, 1, 1, false, false from t
  union all
  select 3, '속도전 a 통과, b 불합격 5회 소진', 'finish/a/win/loss',
         t1, 1, 1, false, null, null, 5, false, false from t
  union all
  select 4, '속도전 a 통과, b 불합격 3회', 'continue/-/-/-',
         t1, 1, 1, false, null, null, 3, false, false from t
  union all
  select 5, '속도전 a 통과(t2), b 판정 중(제출 t1) - 역전 가능', 'continue/-/-/-',
         t2, 2, 1, false, null, null, 0, true, false from t
  union all
  select 6, '속도전 양쪽 불합격 5회 소진', 'draw/-/draw/draw',
         null, null, 5, false, null, null, 5, false, false from t
  union all
  select 7, '속도전 a 5회 소진, b 4회 + 판정 중', 'continue/-/-/-',
         null, null, 5, false, null, null, 4, true, false from t
  union all
  select 8, '마감 후 a만 통과', 'finish/a/win/loss',
         t1, 1, 1, false, null, null, 0, false, true from t
  union all
  select 9, '마감 후 아무도 제출 안 함', 'draw/-/draw/draw',
         null, null, 0, false, null, null, 0, false, true from t
  union all
  select 10, '마감 후 a 불합격 2회, b 판정 중 - 대기', 'continue/-/-/-',
         null, null, 2, false, null, null, 0, true, true from t
  union all
  select 11, '마감 후 a는 AI 실패만 3회(미산입), b 없음', 'draw/-/draw/draw',
         null, null, 0, false, null, null, 0, false, true from t
  union all
  select 12, '속도전 양쪽 같은 시각 통과, seq a < b', 'finish/a/win/completed_loss',
         t1, 1, 1, false, t1, 2, 1, false, false from t
),
quality_cases (case_no, description, expected, a_meets, b_meets, ai_winner) as (
  select 13, '품질전 둘 다 충족, AI 승자 b', 'true/finished/b/loss/win', true, true, 'b'
  union all
  select 14, '품질전 둘 다 충족, AI 승자 없음 - 재시도', 'false/-/-/-/-', true, true, null
  union all
  select 15, '품질전 a만 충족, AI 승자 b(무시)', 'true/finished/a/win/loss', true, false, 'b'
  union all
  select 16, '품질전 둘 다 미달', 'true/draw/-/draw/draw', false, false, null
),
quality_deadline_cases (case_no, description, expected, a_submitted, b_submitted) as (
  select 17, '품질전 마감, a만 제출', 'finished/a/win/loss', true, false
  union all
  select 18, '품질전 마감, 제출 없음', 'draw/-/draw/draw', false, false
),
score_cases (case_no, description, expected, outcome) as (
  select 19, '점수 win', '3', 'win'
  union all
  select 20, '점수 completed_loss', '-1', 'completed_loss'
  union all
  select 21, '점수 loss', '-3', 'loss'
  union all
  select 22, '점수 forfeit', '-3', 'forfeit'
  union all
  select 23, '점수 draw', '-1', 'draw'
),
results as (
  select c.case_no, c.description, c.expected,
         concat_ws('/', o.decision, coalesce(o.winner, '-'), coalesce(o.a_outcome, '-'), coalesce(o.b_outcome, '-')) as actual
  from speed_cases c,
       public.speed_outcome(
         c.a_passed_at, c.a_pass_seq, c.a_attempts, c.a_judging,
         c.b_passed_at, c.b_pass_seq, c.b_attempts, c.b_judging,
         c.deadline_passed
       ) o
  union all
  select c.case_no, c.description, c.expected,
         concat_ws('/', o.valid::text, coalesce(o.status, '-'), coalesce(o.winner, '-'),
                   coalesce(o.a_outcome, '-'), coalesce(o.b_outcome, '-'))
  from quality_cases c,
       public.quality_outcome(c.a_meets, c.b_meets, c.ai_winner) o
  union all
  select c.case_no, c.description, c.expected,
         concat_ws('/', coalesce(o.status, '-'), coalesce(o.winner, '-'),
                   coalesce(o.a_outcome, '-'), coalesce(o.b_outcome, '-'))
  from quality_deadline_cases c,
       public.quality_deadline_outcome(c.a_submitted, c.b_submitted) o
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
