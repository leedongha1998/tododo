-- 봇전 규칙·스키마 표 테스트 (bot-battle 1단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/bot_battle_rules.sql
--
-- SELECT만 한다(쓰기 없음). 결과는 케이스마다 한 행이고 ok 열이 전부 true여야 한다.
-- 마지막 행(case_no 99)은 전체 요약이다.
--
-- ** 1단계(20261120120000)만 적용된 상태에서 돌 수 있어야 한다 ** - 2단계가 만드는 함수
-- (bot_daily_battles_used·start_bot_battle·settle_* 등)를 부르지 않는다. 그쪽은
-- bot_battle_flow_smoke.sql이 본다.
--
-- 확인하는 것
--   1~6    봇전 점수표(승 +1, 그 밖 -1, 잘못된 값 null) — 오너 결정 2·5
--   7~12   ** 사람 대결 점수표가 한 값도 바뀌지 않았는지 ** (회귀. mutual_judge_rules.sql과
--          같은 값을 한 번 더 고정한다 — 두 파일이 어긋나면 사람 대결 점수가 바뀐 것이다)
--   20~23  봇 계정: 고정 id, profiles 1행, 묘비 아님(deleted_at null), player_stats 0행
--   30~35  주제 seed 8행의 모양·기준 수·기간·정렬·제목
--   40~46  스키마: captured_at 완화, 새 제약 3개·인덱스 2개·컬럼 2개, RLS 켜짐 + 정책 0개
--   50~55  권한: bot_user_id는 authenticated까지(CHECK 식에서 쓴다), 점수표와 주제 테이블은 차단
with
bot_score_cases (case_no, description, expected, outcome) as (
  select 1, '봇전 승 +1 (사람 대결은 +3)', '1', 'win'
  union all
  select 2, '봇전 완료한 패배 -1', '-1', 'completed_loss'
  union all
  select 3, '봇전 완료 못 한 패배 -1 (사람 대결은 -3)', '-1', 'loss'
  union all
  select 4, '봇전 포기 -1 (사람 대결은 -3)', '-1', 'forfeit'
  union all
  select 5, '봇전 draw -1 (도달하지 않지만 null을 돌려주지 않는다)', '-1', 'draw'
  union all
  select 6, '잘못된 outcome은 null', 'null', '엉뚱한 값'
),
human_score_cases (case_no, description, expected, outcome) as (
  select 7, '사람 대결 승 +3 (그대로)', '3', 'win'
  union all
  select 8, '사람 대결 완료한 패배 -1 (그대로)', '-1', 'completed_loss'
  union all
  select 9, '사람 대결 완료 못 한 패배 -3 (그대로)', '-3', 'loss'
  union all
  select 10, '사람 대결 포기 -3 (그대로)', '-3', 'forfeit'
  union all
  select 11, '사람 대결 draw -1 (그대로)', '-1', 'draw'
  union all
  select 12, '사람 대결 잘못된 outcome은 null (그대로)', 'null', '엉뚱한 값'
),
results as (
  select c.case_no, c.description, c.expected,
         coalesce(public.bot_outcome_score_delta(c.outcome)::text, 'null') as actual
  from bot_score_cases c
  union all
  select c.case_no, c.description, c.expected,
         coalesce(public.outcome_score_delta(c.outcome)::text, 'null')
  from human_score_cases c

  -- 봇 계정
  union all
  select 20, '봇 id는 고정 상수다', '00000000-0000-0000-0000-00000000b07b',
         public.bot_user_id()::text
  union all
  select 21, '봇 profiles 행 1개, 이름은 "연습 봇"', '1/연습 봇',
         (select concat_ws('/', count(*)::text, max(display_name))
          from public.profiles where id = public.bot_user_id())
  union all
  select 22, '봇은 묘비가 아니다(deleted_at null)', 'true',
         (select (deleted_at is null)::text from public.profiles where id = public.bot_user_id())
  union all
  select 23, '봇의 player_stats 행은 없다(전적을 집계하지 않는다)', '0',
         (select count(*)::text from public.player_stats where user_id = public.bot_user_id())

  -- 주제 seed
  union all
  select 30, '활성 주제 8행', '8',
         (select count(*)::text from public.bot_battle_topics where active)
  union all
  select 31, '모든 주제의 min_criteria가 사람 대결 기준과 같은 모양', 'true',
         (select bool_and(public.is_criteria_list(min_criteria))::text
          from public.bot_battle_topics)
  union all
  select 32, '기준은 주제마다 2개', 'true',
         (select bool_and(jsonb_array_length(min_criteria) = 2)::text
          from public.bot_battle_topics where active)
  union all
  select 33, '기간은 5·10·15분 세 종류(긴 기간 없음)', '5,10,15',
         (select string_agg(d::text, ',' order by d)
          from (select distinct duration_minutes as d
                from public.bot_battle_topics where active) x)
  union all
  select 34, 'sort_order가 1~8로 겹치지 않는다', '1,2,3,4,5,6,7,8',
         (select string_agg(sort_order::text, ',' order by sort_order)
          from public.bot_battle_topics where active)
  union all
  select 35, '화면에 보이는 순서(sort_order, created_at)',
         '설거지하기,책상 정리하기,쓰레기통 비우기,이불 정리하기,신발 정리하기,물 한 컵 마시기,빨래 개기,방 바닥 치우기',
         (select string_agg(title, ',' order by sort_order, created_at)
          from public.bot_battle_topics where active)

  -- 스키마
  union all
  select 40, 'battle_submissions.captured_at이 null을 받는다(봇 행만)', 'YES',
         (select is_nullable from information_schema.columns
          where table_schema = 'public' and table_name = 'battle_submissions'
            and column_name = 'captured_at')
  union all
  select 41, 'captured_at null을 봇 행으로 제한하는 CHECK가 있다', '1',
         (select count(*)::text from pg_constraint
          where conrelid = 'public.battle_submissions'::regclass
            and conname = 'battle_submissions_captured_at_check')
  union all
  select 42, 'battles 봇전 제약 3개(주제 짝·속도전 전용·상대가 봇)', '3',
         (select count(*)::text from pg_constraint
          where conrelid = 'public.battles'::regclass
            and conname in ('battles_bot_topic_pair_check',
                            'battles_bot_speed_only_check',
                            'battles_bot_opponent_check'))
  union all
  select 43, 'battles 봇전 조건부 인덱스 2개', '2',
         (select count(*)::text from pg_indexes
          where schemaname = 'public' and tablename = 'battles'
            and indexname in ('battles_bot_active_idx', 'battles_bot_creator_started_idx'))
  union all
  select 44, 'battles 새 컬럼 2개(is_bot·bot_topic_id)', '2',
         (select count(*)::text from information_schema.columns
          where table_schema = 'public' and table_name = 'battles'
            and column_name in ('is_bot', 'bot_topic_id'))
  union all
  select 45, 'bot_battle_topics는 RLS가 켜져 있다', 'true',
         (select relrowsecurity::text from pg_class
          where oid = 'public.bot_battle_topics'::regclass)
  union all
  select 46, '** 정책이 0개인 것이 정답이다 ** (읽는 경로를 RPC 하나로 못박는다)', '0',
         (select count(*)::text from pg_policies
          where schemaname = 'public' and tablename = 'bot_battle_topics')

  -- 권한
  union all
  select 50, 'authenticated는 bot_user_id를 실행할 수 있다(CHECK 식에서 쓴다)', 'true',
         has_function_privilege('authenticated', 'public.bot_user_id()', 'execute')::text
  union all
  select 51, 'anon은 bot_user_id를 실행할 수 없다', 'false',
         has_function_privilege('anon', 'public.bot_user_id()', 'execute')::text
  union all
  select 52, 'authenticated는 봇전 점수표를 실행할 수 없다', 'false',
         has_function_privilege('authenticated', 'public.bot_outcome_score_delta(text)', 'execute')::text
  union all
  select 53, 'anon은 봇전 점수표를 실행할 수 없다', 'false',
         has_function_privilege('anon', 'public.bot_outcome_score_delta(text)', 'execute')::text
  union all
  select 54, 'authenticated는 주제 테이블을 직접 읽을 수 없다', 'false',
         has_table_privilege('authenticated', 'public.bot_battle_topics', 'select')::text
  union all
  select 55, 'anon은 주제 테이블을 직접 읽을 수 없다', 'false',
         has_table_privilege('anon', 'public.bot_battle_topics', 'select')::text
)
select case_no, description, expected, actual, expected = actual as ok
from results
union all
select 99, '전체', count(*)::text || '케이스',
       count(*) filter (where expected = actual)::text || ' 통과',
       bool_and(expected = actual)
from results
order by case_no;
