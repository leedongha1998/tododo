-- recruit-browse 1단계: 모집 목록을 "한 번에 전부"에서 커서 묶음 + 제목 검색 + 유형·기간대 필터로.
--
-- 걸러내는 일은 전부 이 함수가 한다(design.md "설계 원칙" 1). 클라이언트는 조건을 만들어 보내고
-- 받은 묶음을 한 건도 걸러내지 않는다 — 묶음의 일부만 받는 구조에서 앱이 다시 걸러내면
-- 조건에 맞는 모집이 조용히 빠진다.
--
-- 판정·점수·한도·매칭 규칙은 한 줄도 건드리지 않는다. 테이블·컬럼·RLS·cron·다른 함수도 그대로다.

-- ---------------------------------------------------------------------------
-- list_open_recruits: 인자가 생기므로 드롭 후 재생성
-- ---------------------------------------------------------------------------
-- create or replace로는 인자를 추가할 수 없고, 옛 0-인자 함수를 남기면 오버로드가 둘이 되어
-- list_open_recruits() 호출이 모호해진다(function is not unique).
-- 드롭하면 GRANT도 사라지므로 아래에서 revoke/grant를 다시 쓴다(custom_duration의 create_battle 선례).
drop function if exists public.list_open_recruits();

create function public.list_open_recruits(
  p_limit             integer     default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id         uuid        default null,
  p_query             text        default null,
  p_type              text        default null,   -- 'speed' | 'quality' | null(전체)
  p_duration_band     text        default null    -- 'quick' | 'day' | 'multi' | null(전체)
)
returns setof jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 아래 거부는 사용자의 조작으로는 생기지 않는 프로그래밍 오류다. 상한 50은 "한 번에 전부 받는"
  -- 옛 동작으로 되돌아갈 수 없게 하는 못이다.
  if p_limit is null or p_limit < 1 or p_limit > 50
     or (p_type is not null and p_type not in ('speed', 'quality'))
     or (p_duration_band is not null and p_duration_band not in ('quick', 'day', 'multi'))
     or ((p_cursor_created_at is null) <> (p_cursor_id is null)) then
    raise exception '목록 요청이 올바르지 않습니다.' using hint = 'BAD_PAGE_REQUEST';
  end if;

  return query
    select jsonb_build_object(
      'battle', jsonb_build_object(
        'id', b.id,
        'type', b.type,
        'status', b.status,
        'title', b.title,
        'creator_id', b.creator_id,
        'created_at', b.created_at,
        'duration_minutes', b.duration_minutes,
        'criteria_version', b.criteria_version,
        'min_criteria', b.min_criteria,
        'superiority_criteria', b.superiority_criteria
      ),
      'creator', jsonb_build_object(
        'user_id', p.id,
        'display_name', p.display_name,
        'deleted', p.deleted_at is not null,
        'score', s.score,
        'wins', s.wins,
        'losses', s.losses,
        'draws', s.draws
      )
    )
    from public.battles b
    join public.profiles p on p.id = b.creator_id
    left join public.player_stats s on s.user_id = b.creator_id
    where b.status = 'pending'
      and b.opponent_id is null
      -- 내 모집에는 내가 참가할 수 없다. 목록에서 빼는 것도 그대로다.
      and b.creator_id <> v_user
      -- 커서는 "몇 번째"가 아니라 "어느 값 다음"이다. 묶음 사이에 새 모집이 맨 위에 끼어들거나
      -- 누군가 참가해 중간 행이 사라져도 이미 받은 마지막 행보다 엄격히 작은 행만 다음 묶음에 들어온다.
      and (p_cursor_created_at is null
           or (b.created_at, b.id) < (p_cursor_created_at, p_cursor_id))
      -- ilike '%...%'를 쓰지 않는 이유: 사용자가 넣은 %·_가 와일드카드로 해석되어 한 글자로
      -- 전체가 결과가 된다. strpos는 순수 부분 문자열이라 이스케이프할 것이 없고 한국어 중간
      -- 일치가 그대로 된다. lower()는 영문 제목의 대소문자 차이를 없앤다.
      and (v_query is null or strpos(lower(b.title), lower(v_query)) > 0)
      and (p_type is null or b.type = p_type)
      -- 기간대 경계는 서버만 안다. 클라이언트는 키(quick/day/multi)만 보낸다.
      -- 경계값은 작은 구간에 포함된다(60 -> quick, 1440 -> day).
      and (p_duration_band is null or case p_duration_band
             when 'quick' then b.duration_minutes <= 60
             when 'day'   then b.duration_minutes > 60 and b.duration_minutes <= 1440
             else              b.duration_minutes > 1440
           end)
    -- id desc 타이브레이커가 없으면 created_at이 같은 두 모집의 순서가 호출마다 달라져
    -- 커서 페이징이 깨진다(같은 행이 두 묶음에 들어오거나 빠진다).
    order by b.created_at desc, b.id desc
    limit p_limit;
end;
$$;

comment on function public.list_open_recruits(integer, timestamptz, uuid, text, text, text) is
  '남이 올린 모집 목록(최신순). 대결·기준 두 목록·기준 버전·생성자 전적을 한 번에 돌려준다. '
  '묶음 끊기는 (created_at, id) 커서, 검색은 제목 부분 일치, 필터는 유형과 기간대(quick<=60분 / '
  'day 60<d<=1440 / multi>1440)이며 전부 서버가 적용한다. 인자 없이 부르면 최신 20건.';

-- 드롭으로 GRANT가 사라졌다. Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 주므로
-- revoke를 함께 쓴다.
revoke execute on function public.list_open_recruits(integer, timestamptz, uuid, text, text, text)
  from public, anon;
grant execute on function public.list_open_recruits(integer, timestamptz, uuid, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 피드 인덱스
-- ---------------------------------------------------------------------------
-- 정렬과 커서 탐색(행 비교)을 이 부분 인덱스가 받는다. 검색어(strpos)와 기간대(case)는 인덱스를
-- 타지 않고 남은 모집 행에 필터로 걸린다 — 모집 중 대결은 사용자당 1개라 pending 행 수는
-- 사용자 수를 넘지 않는다. pg_trgm/GIN은 지금 만들지 않는다(필요해지는 시점은 pending이 수만 건이 된 뒤).
create index battles_open_recruit_feed_idx
  on public.battles (created_at desc, id desc)
  where status = 'pending' and opponent_id is null;
