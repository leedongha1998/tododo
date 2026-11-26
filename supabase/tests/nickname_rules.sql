-- 별명 규칙 표 테스트 (nickname 1단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/nickname_rules.sql
--
-- SELECT만 한다(쓰기 없음). 결과는 케이스마다 한 행이고 ok 열이 전부 true여야 한다.
-- 마지막 행(case_no 999)은 전체 요약이다. assert_nickname_pool_valid()가 실패하면 표 대신 그 예외가 나온다.
--
-- ** 1단계(20261124140000)만 적용된 상태에서 돌 수 있어야 한다 ** - 사용자 행을 만들지 않는다.
-- 사용자가 끼는 흐름(직접 쓰기 거부·set_nickname·탈퇴·권한 실제 호출)은 nickname_flow_smoke.sql이 본다.
-- 단어표 검증이 실제로 일하는지(양성 대조, design §11.1-4)는 쓰기가 필요해 그쪽 파일에 있다.
--
-- 확인하는 것 (design §11.1)
--   1~9     normalize_nickname: 앞뒤 공백·연속 공백·탭·줄바꿈·NBSP·U+3000 -> 한 칸, NFD -> NFC, null -> ''
--   100~    check_nickname: design §2.7 표의 모든 줄
--   200~    허용 문자 경계(가·힣·ㄱ·ㅣ·ㅄ 통과 / U+3164·U+318D·U+1100·U+200B·U+FEFF·이모지 CHARS)
--   230~    길이 경계(2자·10자 통과, 1자·11자 LENGTH), 단어 사이 공백
--   300~    예약어 21개 각각 대표 한 건
--   400~    금칙어 묶음마다 한 건(한글·초성·혐오·영문, sh1t·띄어쓰기 우회 포함)
--   500~    단어표·예약어·금칙어 개수, assert_nickname_pool_valid(), random_nickname() 200회
--   600~    스키마·권한: RLS 켜짐 + 정책 0개, profiles 쓰기 정책·권한 없음, 내부 함수 회수, RPC 허용
with
normalize_cases (case_no, description, input, expected) as (
  values
    (1, '앞뒤 공백과 연속 공백', '  수달   왕 ', '수달 왕'),
    (2, '탭·줄바꿈·CR은 공백 한 칸', '수달' || chr(9) || chr(10) || chr(13) || '왕', '수달 왕'),
    (3, 'NBSP·전각 공백(U+3000)은 공백 한 칸, 앞뒤면 지운다',
        chr(160) || '수달' || chr(12288) || '왕' || chr(12288), '수달 왕'),
    (4, 'NFD로 쓴 연습봇이 NFC로 합쳐진다', normalize('연습봇', NFD), '연습봇'),
    (5, 'null은 빈 문자열', null, ''),
    (6, '공백만 있으면 빈 문자열', '   ', ''),
    (7, '보이지 않는 문자(U+200B)는 지우지 않는다(허용 문자 검사가 거부한다)',
        '연습' || chr(8203) || '봇', '연습' || chr(8203) || '봇')
),
check_cases (case_no, description, input, expected) as (
  values
    -- design §2.7 표
    (100, '연습봇', '연습봇', 'NICKNAME_RESERVED/연습봇'),
    (101, '연습  봇(연속 공백)', '연습  봇', 'NICKNAME_RESERVED/연습봇'),
    (102, ' 연습 봇 (앞뒤 공백)', ' 연습 봇 ', 'NICKNAME_RESERVED/연습봇'),
    (103, '탈퇴한 사용자', '탈퇴한 사용자', 'NICKNAME_RESERVED/탈퇴'),
    (104, '탈퇴한사용자', '탈퇴한사용자', 'NICKNAME_RESERVED/탈퇴'),
    (105, '나(1자라 길이에서 먼저 걸린다)', '나', 'NICKNAME_LENGTH'),
    (106, '상대', '상대', 'NICKNAME_RESERVED/상대'),
    (107, '상 대', '상 대', 'NICKNAME_RESERVED/상대'),
    (108, '투두두두 운영자(term 오름차순 첫 행)', '투두두두 운영자', 'NICKNAME_RESERVED/운영자'),
    (109, 'ADMIN', 'ADMIN', 'NICKNAME_RESERVED/admin'),
    (110, 'Todo dudu', 'Todo dudu', 'NICKNAME_RESERVED/tododudu'),
    (111, 'adm1n(1 -> i)', 'adm1n', 'NICKNAME_RESERVED/admin'),
    (112, '연습 U+200B 봇', '연습' || chr(8203) || '봇', 'NICKNAME_CHARS'),
    (113, '연습 U+3164 봇(한글 채움 문자)', '연습' || chr(12644) || '봇', 'NICKNAME_CHARS'),
    (114, 'U+FEFF 연습봇', chr(65279) || '연습봇', 'NICKNAME_CHARS'),
    (115, 'NFD로 쓴 연습봇', normalize('연습봇', NFD), 'NICKNAME_RESERVED/연습봇'),
    (116, '전각 ADMIN',
        chr(65313) || chr(65316) || chr(65325) || chr(65321) || chr(65326), 'NICKNAME_CHARS'),
    (117, '이메일 a@b.co', 'a@b.co', 'NICKNAME_CHARS'),
    (118, '웹 주소 todo.com', 'todo.com', 'NICKNAME_CHARS'),
    (119, '휴대폰 번호 11자리', '01012345678', 'NICKNAME_LENGTH'),
    (120, '★민수★', '★민수★', 'NICKNAME_CHARS'),
    (121, '공백만', '   ', 'NICKNAME_LENGTH'),
    (122, '부지런한 수달', '부지런한 수달', 'ok'),
    (123, 'null', null, 'NICKNAME_LENGTH'),
    -- 리뷰 경고 3: 호환 자모 ㅣ·ㅇ로 영문 예약어를 흉내 낸다. 비교 키가 ㅣ→i, ㅇ→o로 접는다.
    (124, 'ADMㅣN(호환 자모 ㅣ -> i)', 'ADMㅣN', 'NICKNAME_RESERVED/admin'),
    (125, 'TㅇDㅇDUDU(호환 자모 ㅇ -> o)', 'TㅇDㅇDUDU', 'NICKNAME_RESERVED/tododudu'),
    (126, 'ㅇㅇ처럼 자모만 쓴 이름은 그대로 통과', 'ㅇㅇ', 'ok'),
    (127, '자모가 섞인 한글 이름도 그대로 통과', '수달ㅣ왕', 'ok'),
    -- 허용 문자 경계
    (200, '가(U+AC00) 통과', '가가', 'ok'),
    (201, '힣(U+D7A3) 통과', '힣힣', 'ok'),
    (202, 'ㄱ(U+3131) 통과', 'ㄱㄱ', 'ok'),
    (203, 'ㅣ(U+3163) 통과', 'ㅣㅣ', 'ok'),
    (204, 'ㅄ는 허용 문자다(금칙어에서 걸린다 - CHARS가 아니다)', 'ㅄ가', 'NICKNAME_BANNED'),
    (205, 'U+3164(한글 채움 문자) CHARS', '가' || chr(12644), 'NICKNAME_CHARS'),
    (206, 'U+318D(옛 자모) CHARS', '가' || chr(12685), 'NICKNAME_CHARS'),
    (207, 'U+1100(조합형 자모, 합쳐지지 않음) CHARS', '가' || chr(4352), 'NICKNAME_CHARS'),
    (208, 'U+200B CHARS', '가' || chr(8203) || '나', 'NICKNAME_CHARS'),
    (209, 'U+FEFF CHARS', '가' || chr(65279) || '나', 'NICKNAME_CHARS'),
    (210, '이모지 CHARS', '가' || chr(128512), 'NICKNAME_CHARS'),
    (211, 'U+2060(WORD JOINER) CHARS', '가' || chr(8288) || '나', 'NICKNAME_CHARS'),
    (212, 'U+115F·U+1160(조합형 채움) CHARS', '가' || chr(4447) || chr(4448), 'NICKNAME_CHARS'),
    (213, 'U+FFA0(반각 한글 채움) CHARS', '가' || chr(65440), 'NICKNAME_CHARS'),
    (214, '밑줄 CHARS', 'abc_def', 'NICKNAME_CHARS'),
    (215, '하이픈 CHARS', 'abc-def', 'NICKNAME_CHARS'),
    -- 길이 경계와 단어 사이 공백
    (230, '2자 통과', 'ab', 'ok'),
    (231, '10자 통과', '가나다라마바사아자차', 'ok'),
    (232, '1자 LENGTH', '가', 'NICKNAME_LENGTH'),
    (233, '11자 LENGTH', '가나다라마바사아자차카', 'NICKNAME_LENGTH'),
    (234, '단어 사이 공백 1칸 통과(공백도 길이에 센다: 7자)', '동글동글한 곰', 'ok'),
    (235, '정규화 뒤 공백 2칸이 생기지 않는다(연속 공백은 1칸으로 통과)', '수달  왕', 'ok'),
    (236, '가장 긴 기본 별명(10자) 통과', '동글동글한 고슴도치', 'ok'),
    (237, '공백 포함 11자 LENGTH', '동글동글한 고슴도치a', 'NICKNAME_LENGTH'),
    -- 예약어 21개 대표 한 건씩
    (300, '예약어 상대방(exact)', '상대방', 'NICKNAME_RESERVED/상대방'),
    (301, '예약어 알 수 없음(exact)', '알 수 없음', 'NICKNAME_RESERVED/알 수 없음'),
    (302, '예약어 알 수 없음(공백 없이)', '알수없음', 'NICKNAME_RESERVED/알 수 없음'),
    (303, '예약어 상대는 exact라 상대편은 통과', '상대편', 'ok'),
    (304, '예약어 연습봇(contains)', '연습봇123', 'NICKNAME_RESERVED/연습봇'),
    (305, '예약어 탈퇴(contains)', '탈퇴회원', 'NICKNAME_RESERVED/탈퇴'),
    (306, '예약어 운영진', '우리 운영진', 'NICKNAME_RESERVED/운영진'),
    (307, '예약어 운영팀', '운영팀장', 'NICKNAME_RESERVED/운영팀'),
    (308, '예약어 관리자', '관리자님', 'NICKNAME_RESERVED/관리자'),
    (309, '예약어 고객센터', '고객센터', 'NICKNAME_RESERVED/고객센터'),
    (310, '예약어 개발자', '개발자 민수', 'NICKNAME_RESERVED/개발자'),
    (311, '예약어 공식(공식왕도 걸린다 - spec이 받아들인 대가)', '공식왕', 'NICKNAME_RESERVED/공식'),
    (312, '예약어 시스템', '시스템 오류', 'NICKNAME_RESERVED/시스템'),
    (313, '예약어 투두두두', '투두두두', 'NICKNAME_RESERVED/투두두두'),
    (314, '예약어 tododudu(0 -> o)', 'T0D0DUDU', 'NICKNAME_RESERVED/tododudu'),
    (315, '예약어 todododo', 'Todododo1', 'NICKNAME_RESERVED/todododo'),
    (316, '예약어 admin(badminton도 걸린다)', 'badminton', 'NICKNAME_RESERVED/admin'),
    (317, '예약어 system', 'System', 'NICKNAME_RESERVED/system'),
    (318, '예약어 official(l -> i, 1 -> i)', 'officia1', 'NICKNAME_RESERVED/official'),
    (319, '예약어 staff', 'Staff 7', 'NICKNAME_RESERVED/staff'),
    -- 금칙어 묶음마다 한 건(term은 돌려주지 않는다)
    (400, '금칙어 한글 욕설', '씨발', 'NICKNAME_BANNED'),
    (401, '금칙어 한글 욕설 띄어쓰기 우회', '병 신', 'NICKNAME_BANNED'),
    (402, '금칙어 초성 띄어쓰기 우회', 'ㅅ ㅂ', 'NICKNAME_BANNED'),
    (403, '금칙어 혐오 표현', '틀딱이', 'NICKNAME_BANNED'),
    (404, '금칙어 영문', 'fuck', 'NICKNAME_BANNED'),
    (405, '금칙어 영문 1 -> i 우회', 'sh1t', 'NICKNAME_BANNED'),
    (406, '금칙어 영문 대문자', 'PORN', 'NICKNAME_BANNED'),
    (407, '금칙어 알려진 오탐 Essex(sex)', 'Essex', 'NICKNAME_BANNED'),
    (408, '금칙어에서 뺀 말(새끼)은 통과', '새끼고양이', 'ok'),
    (409, '예약어가 금칙어보다 먼저(둘 다 들면 RESERVED)', '시발 운영자', 'NICKNAME_RESERVED/운영자')
),
samples as (
  -- volatile 함수를 대상 목록에 두면 행마다 다시 부른다(FROM 절 서브질의로 두면 한 번만 불릴 수 있다).
  select public.random_nickname() as n
  from generate_series(1, 200)
),
results as (
  select c.case_no, c.description, c.expected,
         public.normalize_nickname(c.input) as actual
  from normalize_cases c
  union all
  select 8, 'NFD 입력이 실제로 NFC와 다른 바이트다(4번이 빈 검사가 아닌지)', 'true',
         (normalize('연습봇', NFD) <> '연습봇')::text
  union all
  select 9, '비교 키: 공백 제거·소문자·0/1/l 접기', 'tododoiii',
         public.nickname_compare_key('To D0 do 1 l I')

  union all
  select c.case_no, c.description, c.expected,
         (select coalesce(r.code, 'ok') || coalesce('/' || r.term, '')
          from public.check_nickname(c.input) r)
  from check_cases c
  union all
  select 124, '통과하면 정규화 값을 돌려준다', '수달 왕',
         (select r.normalized from public.check_nickname('  수달   왕 ') r)

  -- 단어표·풀 검증·무작위 별명
  union all
  select 500, '형용사 40개', '40',
         (select count(*)::text from public.nickname_words where kind = 'adjective')
  union all
  select 501, '명사 40개', '40',
         (select count(*)::text from public.nickname_words where kind = 'noun')
  union all
  select 502, '예약어 21개(exact 4, contains 17)', '21/4/17',
         (select concat_ws('/', count(*), count(*) filter (where match = 'exact'),
                           count(*) filter (where match = 'contains'))
          from public.nickname_blocked_terms where category = 'reserved')
  union all
  select 503, '금칙어 42개(전부 contains)', '42/42',
         (select concat_ws('/', count(*), count(*) filter (where match = 'contains'))
          from public.nickname_blocked_terms where category = 'banned')
  union all
  select 504, 'assert_nickname_pool_valid()가 예외 없이 끝난다(1,600 조합 전부 통과)', 'ok',
         (select 'ok' from (select public.assert_nickname_pool_valid()::text as r) x where x.r is not null)
  union all
  select 505, 'random_nickname() 200회가 전부 check_nickname 통과', '200',
         (select count(*)::text from samples s where (public.check_nickname(s.n)).code is null)
  union all
  select 506, 'random_nickname() 200회가 전부 10자 이하', '200',
         (select count(*)::text from samples s where char_length(s.n) <= 10)
  union all
  select 507, 'random_nickname() 200회가 전부 "형용사 명사" 모양', '200',
         (select count(*)::text
          from samples s
          where split_part(s.n, ' ', 1) in (select word from public.nickname_words where kind = 'adjective')
            and split_part(s.n, ' ', 2) in (select word from public.nickname_words where kind = 'noun')
            and split_part(s.n, ' ', 3) = '')

  -- 스키마·권한
  union all
  select 600, '새 테이블 셋 RLS 켜짐', '3',
         (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname in ('nickname_states', 'nickname_words', 'nickname_blocked_terms')
            and c.relrowsecurity)
  union all
  select 601, '새 테이블 셋 정책 0개', '0',
         (select count(*)::text from pg_policies
          where schemaname = 'public'
            and tablename in ('nickname_states', 'nickname_words', 'nickname_blocked_terms'))
  union all
  select 602, 'profiles에 select 아닌 정책이 없다', '0',
         (select count(*)::text from pg_policies
          where schemaname = 'public' and tablename = 'profiles' and cmd <> 'SELECT')
  union all
  select 603, 'profiles select 정책은 그대로', '1',
         (select count(*)::text from pg_policies
          where schemaname = 'public' and tablename = 'profiles' and cmd = 'SELECT')
  union all
  select 604, 'authenticated는 profiles를 읽을 수 있다', 'true',
         has_table_privilege('authenticated', 'public.profiles', 'select')::text
  union all
  select 605, 'authenticated는 profiles를 update/insert/delete할 수 없다', 'false/false/false',
         concat_ws('/',
           has_table_privilege('authenticated', 'public.profiles', 'update')::text,
           has_table_privilege('authenticated', 'public.profiles', 'insert')::text,
           has_table_privilege('authenticated', 'public.profiles', 'delete')::text)
  union all
  select 606, 'anon은 profiles를 update할 수 없다', 'false',
         has_table_privilege('anon', 'public.profiles', 'update')::text
  union all
  select 607, 'authenticated는 새 테이블 셋을 읽을 수 없다', 'false/false/false',
         concat_ws('/',
           has_table_privilege('authenticated', 'public.nickname_states', 'select')::text,
           has_table_privilege('authenticated', 'public.nickname_words', 'select')::text,
           has_table_privilege('authenticated', 'public.nickname_blocked_terms', 'select')::text)
  union all
  select 608, 'authenticated는 내부 함수 다섯을 실행할 수 없다', 'false/false/false/false/false',
         concat_ws('/',
           has_function_privilege('authenticated', 'public.normalize_nickname(text)', 'execute')::text,
           has_function_privilege('authenticated', 'public.nickname_compare_key(text)', 'execute')::text,
           has_function_privilege('authenticated', 'public.check_nickname(text)', 'execute')::text,
           has_function_privilege('authenticated', 'public.random_nickname()', 'execute')::text,
           has_function_privilege('authenticated', 'public.assert_nickname_pool_valid()', 'execute')::text)
  union all
  select 609, 'authenticated는 사용자 RPC 셋을 실행할 수 있다', 'true/true/true',
         concat_ws('/',
           has_function_privilege('authenticated', 'public.get_my_nickname_state()', 'execute')::text,
           has_function_privilege('authenticated', 'public.set_nickname(text)', 'execute')::text,
           has_function_privilege('authenticated', 'public.suggest_nickname()', 'execute')::text)
  union all
  select 610, 'anon은 사용자 RPC 셋을 실행할 수 없다', 'false/false/false',
         concat_ws('/',
           has_function_privilege('anon', 'public.get_my_nickname_state()', 'execute')::text,
           has_function_privilege('anon', 'public.set_nickname(text)', 'execute')::text,
           has_function_privilege('anon', 'public.suggest_nickname()', 'execute')::text)
  union all
  select 611, '사용자 RPC 셋은 SECURITY DEFINER, 내부 함수 다섯은 invoker', '3/0',
         (select concat_ws('/',
                   count(*) filter (where p.prosecdef and p.proname in
                     ('get_my_nickname_state', 'set_nickname', 'suggest_nickname')),
                   count(*) filter (where p.prosecdef and p.proname in
                     ('normalize_nickname', 'nickname_compare_key', 'check_nickname',
                      'random_nickname', 'assert_nickname_pool_valid')))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public')
  union all
  select 612, 'handle_new_user가 raw_user_meta_data·email을 읽지 않는다', 'false/false',
         (select concat_ws('/',
                   (position('raw_user_meta_data' in p.prosrc) > 0)::text,
                   (position('new.email' in p.prosrc) > 0)::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'handle_new_user')
  union all
  select 613, 'delete_account가 nickname_states를 지운다', 'true',
         (select (position('delete from public.nickname_states' in p.prosrc) > 0)::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'delete_account')
)
select case_no, description, expected, actual, expected is not distinct from actual as ok
from results
union all
select 999, '전체', count(*)::text || '케이스',
       count(*) filter (where expected is not distinct from actual)::text || ' 통과',
       bool_and(expected is not distinct from actual)
from results
order by case_no;
