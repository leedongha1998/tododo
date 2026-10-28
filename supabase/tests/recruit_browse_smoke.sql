-- 모집 목록(커서 묶음 + 제목 검색 + 유형·기간대 필터) 스모크 테스트.
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/recruit_browse_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=t                     -> 통과
--   SMOKE RESULT ok=f  FAILURES: ...      -> 어긋난 항목(기대값/실제값)
--
-- 원격에는 이미 다른 모집 행(더미 등)이 있다. 그래서
--   (1) 이 스모크가 넣는 모집의 created_at을 기존 최대값보다 뒤로 밀어 항상 목록 맨 위에 오게 하고,
--   (2) 건수를 세는 확인은 이 스모크가 만든 생성자 id로 한정한다.
-- 같은 트랜잭션 안에서 now()는 고정이므로 created_at을 직접 넣어 순서를 만든다(pg_sleep으로는 안 된다).
--
-- 확인하는 것
--   newest_first      최신 모집이 첫 행이다(정렬은 created_at desc, id desc 고정)
--   default_limit     인자 없이 부르면 정확히 min(20, 볼 수 있는 모집 수)건이 온다
--   default_same_as_20   그 호출이 p_limit=20 호출과 같은 행·같은 순서다(기본값이 20으로 박혀 있다)
--   default_mine      그 기본 호출에 이 스모크의 모집 10건이 모두 들어 있다
--   search_mid        제목 중간 글자로 찾힌다("설거지하기"에서 '거지')
--   search_spaces     검색어 앞뒤 공백은 결과를 바꾸지 않는다
--   search_lower/upper   영문 제목은 대소문자 차이로 달라지지 않는다
--   search_percent/underscore  %·_가 와일드카드로 작동하지 않는다(순수 부분 문자열)
--   search_criteria   판정 기준 문구로는 찾히지 않는다
--   search_creator    생성자 이름으로는 찾히지 않는다
--   type_speed/quality/all   유형 필터 건수
--   band_quick/day/multi     기간대 경계(1·30·30·60 / 61·1440·1440 / 1441·4320·10080)
--   combo             검색어 + 유형 + 기간대가 함께 걸린다(검색이 필터를 풀지 않는다)
--   mine_excluded     내가 만든 모집은 어떤 조건에서도 나오지 않는다
--   bad_*             인자 검증(limit 0·51·null, 유형·기간대 오타, 커서 한쪽만)
--   bad_hints         그 여섯 거부가 모두 hint='BAD_PAGE_REQUEST'를 함께 준다(클라이언트가 읽는 값)
--   anon_denied       anon 롤에는 실행 권한이 없다(드롭·재생성으로 새지 않았다)
--   page1/page2       묶음이 최신순으로 이어진다
--   page_overlap      묶음 사이에 새 모집이 올라와도 같은 모집이 두 번 나오지 않는다
--   page_new_absent   그 새 모집은 두 묶음 어디에도 들어오지 않는다(커서보다 위이기 때문)
--   page_no_gap       안 본 모집이 매칭돼 사라져도 남은 행을 건너뛰지 않는다
--   tie_order/tie_once   created_at이 같은 두 행이 id desc 순서로 한 번씩만 나온다
do $$
declare
  v_me     uuid := gen_random_uuid();  -- 목록을 보는 사람(자기 모집도 하나 올린다)
  v_joiner uuid := gen_random_uuid();  -- 묶음 사이에 모집 하나를 매칭시켜 사라지게 하는 사람
  v_u      uuid[] := array(select gen_random_uuid() from generate_series(1, 11));
  v_mine   uuid[];
  v_base   timestamptz;
  v_r      uuid[] := array[]::uuid[];
  v_new    uuid;
  v_page1  jsonb;
  v_page2  jsonb;
  v_page3  jsonb;
  v_tie1   jsonb;
  v_tie2   jsonb;
  v_bad_limit_zero text := '(예외 없음)';
  v_bad_limit_over text := '(예외 없음)';
  v_bad_limit_null text := '(예외 없음)';
  v_bad_type       text := '(예외 없음)';
  v_bad_band       text := '(예외 없음)';
  v_bad_cursor     text := '(예외 없음)';
  v_hint           text;
  v_bad_hints      text[] := '{}';
  v_anon_denied    text := '(예외 없음)';
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  v_mine := v_u[1:10];

  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'browse-smoke-' || u.tag || '@example.invalid',
         jsonb_build_object('full_name', '스모크' || u.tag), now(), now()
  from (
    select v_me as id, 'me' as tag
    union all select v_joiner, 'joiner'
    union all select v_u[i], i::text from generate_series(1, 11) i
  ) u;

  -- 이 스모크의 모집이 기존 행보다 항상 뒤(= 목록 맨 위)에 오게 한다.
  v_base := greatest(now(), (select coalesce(max(created_at), now()) from public.battles))
            + interval '1 second';

  -- 모집 10건. 모집 중 대결은 사용자당 1개라 생성자를 한 건씩 나눈다.
  -- ord가 클수록 최신이다. ord 1인 두 건은 created_at이 완전히 같다(동률 확인용).
  insert into public.battles
    (type, status, title, creator_id, duration_minutes, min_criteria, superiority_criteria, created_at)
  select d.type, 'pending', d.title, v_u[d.k], d.minutes,
         '["싱크대가 비어 있다"]'::jsonb,
         case when d.type = 'quality' then '["먼지가 없다"]'::jsonb end,
         v_base + interval '1 minute' * d.ord
  from (values
    ( 1, '설거지하기',  'speed',      30, 10),
    ( 2, 'Gym 가기',    'quality',    60,  9),
    ( 3, '방 청소하기',  'speed',      61,  8),
    ( 4, '빨래 개기',    'quality',  1440,  7),
    ( 5, '설거지 돕기',  'speed',    1441,  6),
    ( 6, '물 마시기',    'speed',       1,  5),
    ( 7, '독후감 쓰기',  'quality', 10080,  4),
    ( 8, '산책하기',     'speed',    1440,  3),
    ( 9, '동률 가',      'speed',      30,  1),
    (10, '동률 나',      'speed',    4320,  1)
  ) as d(k, title, type, minutes, ord);

  for i in 1..10 loop
    v_r[i] := (select id from public.battles where creator_id = v_u[i] and status = 'pending');
  end loop;

  -- 내 모집(목록을 보는 사람 본인). 가장 최신이지만 어떤 조건에서도 나오면 안 된다.
  insert into public.battles
    (type, status, title, creator_id, duration_minutes, min_criteria, superiority_criteria, created_at)
  values ('speed', 'pending', '내 모집', v_me, 30, '["싱크대가 비어 있다"]'::jsonb, null,
          v_base + interval '11 minutes');

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_me, 'role', 'authenticated')::text, true);

  -- 1~6. 정렬·기본값·검색·유형·기간대·조합·내 모집 제외.
  -- 건수 확인은 모두 묶음을 이어 받기 전(행이 늘거나 사라지기 전)에 센다.
  v_actual := jsonb_build_object(
    'newest_first', (select r -> 'battle' ->> 'title'
                     from public.list_open_recruits(1, null, null, null, null, null) r),
    -- 무인자 호출은 "최신 20건"이다(count(*) <= 20은 묶음이 1건이어도 참이라 뜻이 없다).
    -- ① 받는 건수가 min(20, 지금 볼 수 있는 모집 수)와 정확히 같다
    'default_limit', (select count(*) from public.list_open_recruits() r)
                     = least(
                         20,
                         (select count(*) from public.battles b
                          where b.status = 'pending' and b.opponent_id is null
                            and b.creator_id <> v_me)
                       ),
    -- ② p_limit을 20으로 명시한 호출과 같은 행이 같은 순서로 온다
    'default_same_as_20', (select jsonb_agg(t.item -> 'battle' ->> 'id' order by t.ord)
                           from public.list_open_recruits() with ordinality as t(item, ord))
                          = (select jsonb_agg(t.item -> 'battle' ->> 'id' order by t.ord)
                             from public.list_open_recruits(20, null, null, null, null, null)
                               with ordinality as t(item, ord)),
    'default_mine', (select count(*)::int from public.list_open_recruits() r
                     where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_mid', (select count(*)::int
                   from public.list_open_recruits(50, null, null, '거지', null, null) r
                   where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_spaces', (select count(*)::int
                      from public.list_open_recruits(50, null, null, '  설거지  ', null, null) r
                      where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_lower', (select count(*)::int
                     from public.list_open_recruits(50, null, null, 'gym', null, null) r
                     where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_upper', (select count(*)::int
                     from public.list_open_recruits(50, null, null, 'GYM', null, null) r
                     where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_percent', (select count(*)::int
                       from public.list_open_recruits(50, null, null, '%', null, null) r
                       where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_underscore', (select count(*)::int
                          from public.list_open_recruits(50, null, null, '_', null, null) r
                          where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_criteria', (select count(*)::int
                        from public.list_open_recruits(50, null, null, '싱크대', null, null) r
                        where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'search_creator', (select count(*)::int
                       from public.list_open_recruits(50, null, null, '스모크', null, null) r
                       where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'type_speed', (select count(*)::int
                   from public.list_open_recruits(50, null, null, null, 'speed', null) r
                   where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'type_quality', (select count(*)::int
                     from public.list_open_recruits(50, null, null, null, 'quality', null) r
                     where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'type_all', (select count(*)::int
                 from public.list_open_recruits(50, null, null, null, null, null) r
                 where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'band_quick', (select count(*)::int
                   from public.list_open_recruits(50, null, null, null, null, 'quick') r
                   where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'band_day', (select count(*)::int
                 from public.list_open_recruits(50, null, null, null, null, 'day') r
                 where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'band_multi', (select count(*)::int
                   from public.list_open_recruits(50, null, null, null, null, 'multi') r
                   where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    -- '거지'는 두 건이지만 speed + quick까지 걸면 "설거지하기"만 남는다.
    'combo', (select jsonb_agg(r -> 'battle' ->> 'title')
              from public.list_open_recruits(50, null, null, '거지', 'speed', 'quick') r
              where (r -> 'battle' ->> 'creator_id')::uuid = any(v_mine)),
    'mine_excluded', (select count(*)::int
                      from public.list_open_recruits(50, null, null, '내 모집', null, null) r
                      where (r -> 'battle' ->> 'creator_id')::uuid = v_me)
  );

  -- 7. 인자 검증. 사용자의 조작으로는 생기지 않는 프로그래밍 오류다.
  --    계약은 "문구 + hint = BAD_PAGE_REQUEST" 두 짝이고, 클라이언트가 분기에 쓰는 값은 hint다.
  --    그래서 여섯 거부의 hint를 순서대로 모아 함께 확인한다.
  begin
    perform public.list_open_recruits(0, null, null, null, null, null);
  exception when others then
    v_bad_limit_zero := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
    v_bad_hints := v_bad_hints || coalesce(v_hint, '(없음)');
  end;
  begin
    perform public.list_open_recruits(51, null, null, null, null, null);
  exception when others then
    v_bad_limit_over := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
    v_bad_hints := v_bad_hints || coalesce(v_hint, '(없음)');
  end;
  begin
    perform public.list_open_recruits(null, null, null, null, null, null);
  exception when others then
    v_bad_limit_null := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
    v_bad_hints := v_bad_hints || coalesce(v_hint, '(없음)');
  end;
  begin
    perform public.list_open_recruits(20, null, null, null, 'speedy', null);
  exception when others then
    v_bad_type := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
    v_bad_hints := v_bad_hints || coalesce(v_hint, '(없음)');
  end;
  begin
    perform public.list_open_recruits(20, null, null, null, null, 'week');
  exception when others then
    v_bad_band := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
    v_bad_hints := v_bad_hints || coalesce(v_hint, '(없음)');
  end;
  begin
    perform public.list_open_recruits(20, now(), null, null, null, null);
  exception when others then
    v_bad_cursor := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
    v_bad_hints := v_bad_hints || coalesce(v_hint, '(없음)');
  end;

  -- 8. 권한: 드롭·재생성한 함수가 anon에 새지 않았는지.
  begin
    execute 'set local role anon';
    perform public.list_open_recruits(20, null, null, null, null, null);
    execute 'reset role';
  exception when insufficient_privilege then
    v_anon_denied := '권한 없음';
  when others then
    v_anon_denied := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_me, 'role', 'authenticated')::text, true);

  -- 9. 묶음을 이어 받는 사이에 행이 생기고 사라져도 중복·누락이 없다.
  select jsonb_agg(t.item order by t.ord) into v_page1
  from public.list_open_recruits(2, null, null, null, null, null) with ordinality as t(item, ord);

  -- 묶음 사이에 새 모집이 올라온다. 최신순이라 맨 위에 들어오지만 커서보다 위라 다음 묶음에 없다.
  insert into public.battles
    (type, status, title, creator_id, duration_minutes, min_criteria, superiority_criteria, created_at)
  values ('speed', 'pending', '새 모집', v_u[11], 30, '["싱크대가 비어 있다"]'::jsonb, null,
          v_base + interval '20 minutes')
  returning id into v_new;

  select jsonb_agg(t.item order by t.ord) into v_page2
  from public.list_open_recruits(
         2,
         (v_page1 -> 1 -> 'battle' ->> 'created_at')::timestamptz,
         (v_page1 -> 1 -> 'battle' ->> 'id')::uuid,
         null, null, null
       ) with ordinality as t(item, ord);

  -- 아직 못 본 행(ord 6, "설거지 돕기")이 그 사이 매칭돼 목록에서 사라진다.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_joiner, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform public.join_battle(v_r[5], 1);
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_me, 'role', 'authenticated')::text, true);

  select jsonb_agg(t.item order by t.ord) into v_page3
  from public.list_open_recruits(
         2,
         (v_page2 -> 1 -> 'battle' ->> 'created_at')::timestamptz,
         (v_page2 -> 1 -> 'battle' ->> 'id')::uuid,
         null, null, null
       ) with ordinality as t(item, ord);

  -- 10. 동률. "산책하기"(ord 3) 다음 두 행은 created_at이 같다 - id desc로 한 번씩 나와야 한다.
  select t.item into v_tie1
  from public.list_open_recruits(
         1,
         (select created_at from public.battles where id = v_r[8]),
         v_r[8],
         null, null, null
       ) as t(item);

  select t.item into v_tie2
  from public.list_open_recruits(
         1,
         (v_tie1 -> 'battle' ->> 'created_at')::timestamptz,
         (v_tie1 -> 'battle' ->> 'id')::uuid,
         null, null, null
       ) as t(item);

  v_actual := v_actual || jsonb_build_object(
    'bad_limit_zero', v_bad_limit_zero,
    'bad_limit_over', v_bad_limit_over,
    'bad_limit_null', v_bad_limit_null,
    'bad_type', v_bad_type,
    'bad_band', v_bad_band,
    'bad_cursor', v_bad_cursor,
    'bad_hints', array_to_string(v_bad_hints, ','),
    'anon_denied', v_anon_denied,
    'page1', jsonb_build_array(v_page1 -> 0 -> 'battle' ->> 'title',
                               v_page1 -> 1 -> 'battle' ->> 'title'),
    'page2', jsonb_build_array(v_page2 -> 0 -> 'battle' ->> 'title',
                               v_page2 -> 1 -> 'battle' ->> 'title'),
    'page_overlap', (select count(*)::int
                     from jsonb_array_elements(v_page1) a
                     join jsonb_array_elements(v_page2) b
                       on (a -> 'battle' ->> 'id') = (b -> 'battle' ->> 'id')),
    'page_new_absent', not exists (
      select 1 from jsonb_array_elements(v_page1 || v_page2) x
      where (x -> 'battle' ->> 'id')::uuid = v_new),
    -- ord 6이 사라졌으므로 ord 5·4가 와야 한다(ord 5를 건너뛰지 않는다).
    'page_no_gap', jsonb_build_array(v_page3 -> 0 -> 'battle' ->> 'title',
                                     v_page3 -> 1 -> 'battle' ->> 'title'),
    'tie_order', (v_tie1 -> 'battle' ->> 'id')::uuid > (v_tie2 -> 'battle' ->> 'id')::uuid,
    'tie_once', (select array_agg(x order by x)
                 from (values ((v_tie1 -> 'battle' ->> 'id')::uuid),
                              ((v_tie2 -> 'battle' ->> 'id')::uuid)) as t(x))
                = (select array_agg(x order by x)
                   from (values (v_r[9]), (v_r[10])) as t(x))
  );

  v_expected := jsonb_build_object(
    'newest_first', '설거지하기',
    'default_limit', true,
    'default_same_as_20', true,
    'default_mine', 10,
    'search_mid', 2,
    'search_spaces', 2,
    'search_lower', 1,
    'search_upper', 1,
    'search_percent', 0,
    'search_underscore', 0,
    'search_criteria', 0,
    'search_creator', 0,
    'type_speed', 7,
    'type_quality', 3,
    'type_all', 10,
    'band_quick', 4,
    'band_day', 3,
    'band_multi', 3,
    'combo', jsonb_build_array('설거지하기'),
    'mine_excluded', 0,
    'bad_limit_zero', '목록 요청이 올바르지 않습니다.',
    'bad_limit_over', '목록 요청이 올바르지 않습니다.',
    'bad_limit_null', '목록 요청이 올바르지 않습니다.',
    'bad_type', '목록 요청이 올바르지 않습니다.',
    'bad_band', '목록 요청이 올바르지 않습니다.',
    'bad_cursor', '목록 요청이 올바르지 않습니다.',
    'bad_hints', 'BAD_PAGE_REQUEST,BAD_PAGE_REQUEST,BAD_PAGE_REQUEST,'
                 'BAD_PAGE_REQUEST,BAD_PAGE_REQUEST,BAD_PAGE_REQUEST',
    'anon_denied', '권한 없음',
    'page1', jsonb_build_array('설거지하기', 'Gym 가기'),
    'page2', jsonb_build_array('방 청소하기', '빨래 개기'),
    'page_overlap', 0,
    'page_new_absent', true,
    'page_no_gap', jsonb_build_array('물 마시기', '독후감 쓰기'),
    'tie_order', true,
    'tie_once', true
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
