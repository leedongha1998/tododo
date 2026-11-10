-- 개인 투두의 손 순서(todo-reorder P0).
--
-- 지금까지 목록 순서는 서버가 아니라 Dart가 만들었다(todo-due-date의 sortedForList — 기한 이른
-- 순). 그 규칙을 걷어내고 **사용자가 끌어 정한 순서**를 이 컬럼 하나로 옮긴다. 이 뒤로 목록
-- 순서를 만드는 자리는 "order by position" 한 줄뿐이다.
--
-- 20261109120000_todos_due_at.sql의 주석은 "기한 순서는 서버가 아니라 Dart(sortedForList)가
-- 만든다 / 정렬을 서버로 옮기면 그때 (user_id, due_at) 인덱스를 추가한다"고 적혀 있다.
-- 그 파일은 이미 원격에 적용돼 고치지 않는다. 지금 상태는 이렇다: **정렬은 서버로 왔지만
-- 기한으로 정렬하지 않으므로 그 인덱스는 끝내 만들지 않는다.** due_at은 표시용이고, 순서는
-- 이 컬럼이다. 두 파일을 함께 읽으면 현재 상태가 보인다.
--
-- 자리 값은 1024 간격의 띄운 정수다(design 1.1). 끌기 한 번은 보통 한 행만 쓰고(옮긴 행의
-- position을 두 이웃의 중간값으로), 틈이 고갈되면 move_todo 안에서 다시 번호를 매긴다.
-- 대결과 아무 관계가 없다 — 이 컬럼을 읽는 판정·점수·cron·Edge Function 경로는 없다.

-- 1) 컬럼. 백필 전까지만 nullable이다(3번에서 not null로 닫는다).
alter table public.todos
  add column position bigint;

-- 2) 기존 행 백필 — **생성순 한 줄**(오너 확정, spec 결정 기록 1).
--    기한을 보는 백필을 만들지 않는다: 한 번 쓰고 버릴 정렬 규칙을 SQL에 다시 구현하는 비용만
--    남는다. 배포 전이라 쌓인 데이터가 오너 테스트 계정뿐이고 그 할 일은 전부 기한이 없어
--    두 방식의 결과가 같다.
--    사용자별로 나누지 않아도 된다 — 번호를 전역 생성순으로 매겨도 각 사용자 안에서는 생성순이다.
with ordered as (
  select id, row_number() over (order by created_at, id) as rn
  from public.todos
)
update public.todos t
set position = ordered.rn * 1024
from ordered
where ordered.id = t.id;

-- 3) 새 행의 자리 = 맨 아래. **시퀀스**로 정한다.
--    "max(position) + 1024"을 트리거로 계산하지 않는 이유: 두 기기가 같은 순간에 추가하면 같은
--    max를 읽어 같은 자리 값을 만들고, 아래 유일 제약에 걸려 **추가 자체가 실패**한다. 시퀀스는
--    동시 호출에도 서로 다른 값을 주므로 둘 다 성공하고 둘 다 맨 아래로 간다(호출된 순서대로).
--    "맨 아래"가 깨지지 않는 근거는 **분기마다 따로** 봐야 한다. 이 컬럼의 값 공간을 건드리는
--    경로가 둘이기 때문이다(이 기본값 / move_todo).
--      ① 재번호 갈래: nextval은 단조 증가하고 지금까지 발급한 수는 언제나 그 사용자의 행 수
--         이상이므로, 재번호가 만드는 최댓값(행 수 * 1024)보다 다음 발급 값이 크다.
--      ② **맨 아래로 끌기 갈래**: 그 행이 max + 1024를 가져가므로 시퀀스를 앞질러 다음
--         insert와 **같은 값**이 될 수 있다. 그래서 move_todo의 그 분기가 시퀀스를 그 값 위로
--         밀어 둔다(setval + greatest). 밀지 않으면 다음 "할 일 추가"가 유일 제약에 걸려 실패한다.
create sequence public.todos_position_seq as bigint;

select setval(
  'public.todos_position_seq',
  coalesce((select max(position) / 1024 from public.todos), 0) + 1,
  false  -- 다음 nextval이 이 값을 돌려준다(= 백필한 마지막 번호 바로 뒤)
);

alter table public.todos
  alter column position set default (nextval('public.todos_position_seq') * 1024),
  alter column position set not null;

-- 컬럼 기본값의 nextval은 **삽입하는 역할의 권한**으로 평가된다. authenticated에 usage가 없으면
-- 할 일 추가가 전부 실패한다. public·anon에는 주지 않는다(RLS로도 막히지만 권한까지 닫아 둔다).
revoke all on sequence public.todos_position_seq from public, anon;
grant usage on sequence public.todos_position_seq to authenticated;

comment on column public.todos.position is
  '개인 투두 목록의 손 순서(작은 값이 위). 1024 간격의 띄운 정수. 사용자 안에서만 뜻이 있고 값의 크기 자체에는 뜻이 없다 — 맨 위로 반복해 끌면 음수가 될 수 있고 정상이다.';

-- 4) 동순위를 **DB가** 막는다. 덤으로 목록 쿼리(where user_id = ? order by position)가 쓰는
--    인덱스가 여기서 생긴다 — 그래서 인덱스를 따로 만들지 않는다(기존 todos_user_id_idx는 이
--    인덱스의 접두사가 되어 사실상 중복이지만, 지우는 것은 이 기능의 범위가 아니라 그대로 둔다).
--    deferrable인 이유는 재번호(move_todo의 드문 갈래)가 한 문장 안에서 값을 돌려 끼우기 때문이다.
--    행별 즉시 검사에 헛되게 부딪히므로 그 갈래에서만 commit 시점으로 미룬다(move_todo 참고).
alter table public.todos
  add constraint todos_user_position_key unique (user_id, position)
  deferrable initially immediate;

-- 5) 끌기 한 번 = 이 함수 한 번 = 트랜잭션 한 번. "절반만 반영된 순서"가 남을 경로가 없다.
--
-- 클라이언트는 **자리 값을 계산하지 않는다.** 보내는 것은 "이 할 일을 p_after_id 바로 아래에
-- 둔다"(null이면 맨 위)뿐이고, 자리 값은 서버가 **그 순간의 실제 이웃**에서 만든다. 그래서 다른
-- 기기가 그 사이 순서를 바꿔 좌표가 낡았어도 같은 자리 값이 생기지 않는다. 결과가 "이상한
-- 순서"일 수는 있고 그것은 spec이 받아들인 것이다(마지막 쓰기가 이긴다).
create function public.move_todo(p_todo_id uuid, p_after_id uuid default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_after_pos bigint;
  v_next_pos bigint;
  v_new_pos bigint;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 내 할 일 전부를 잠근다. 같은 사용자의 두 끌기가 겹쳐 같은 틈의 중간값을 각자 계산하는 것을
  -- 막는다(뒤에 온 트랜잭션은 잠금이 풀린 뒤 READ COMMITTED의 새 스냅샷으로 다시 계산한다).
  -- 두 트랜잭션이 같은 조건으로 같은 순서로만 잠그므로 교착이 없다. 행 수는 수십 규모다.
  -- order by id를 적는 이유: 잠그는 순서를 **계획에 맡기지 않는다**(인덱스 선택이 바뀌면 순서가
  -- 달라져 위 문장이 거짓이 된다). position으로 정렬하지 않는 것은 그 값이 이 함수가 바꾸는
  -- 값이기 때문이다 — id는 변하지 않는다.
  perform 1 from public.todos where user_id = v_user order by id for update;

  -- SECURITY DEFINER라 RLS가 적용되지 않는다. 내 행인지 여기서 직접 본다.
  perform 1 from public.todos where id = p_todo_id and user_id = v_user;
  if not found then
    raise exception '할 일을 찾을 수 없습니다.';
  end if;

  if p_after_id is not null then
    if p_after_id = p_todo_id then
      raise exception '옮길 자리가 잘못됐습니다.';
    end if;
    select position into v_after_pos
    from public.todos
    where id = p_after_id and user_id = v_user;
    -- position은 not null이므로 "값이 비었다"는 경우가 없다. not found는 그 행이 없다는 뜻이다
    -- (다른 기기에서 지웠다). 조용히 맨 위로 보내지 않고 실패로 알린다 — 화면은 끌기 전 순서로
    -- 되돌리고 다음 조회에서 진실을 받는다(design 4.4).
    if not found then
      raise exception '옮길 자리를 찾을 수 없습니다.';
    end if;
  end if;

  -- 놓일 자리의 아래쪽 이웃. 옮기는 행 자신은 뺀다. 집계라서 행이 없으면 null이다.
  select min(position) into v_next_pos
  from public.todos
  where user_id = v_user
    and id <> p_todo_id
    and (v_after_pos is null or position > v_after_pos);

  if v_after_pos is null then
    -- 맨 위. 1024씩 내려가며 음수가 될 수 있고 그래도 무해하다(정렬에만 쓰는 값이다).
    -- 여기서 재번호를 걸지 않는 이유: 재번호 직후 맨 위는 1024이므로, 음수를 막으려 들면
    -- "맨 위로 끌기"가 매번 전체 재번호가 된다.
    v_new_pos := coalesce(v_next_pos, 1024) - 1024;
  elsif v_next_pos is null then
    -- 맨 아래. 새 할 일의 자리(컬럼 기본값 = nextval * 1024)와 **같은 값 공간**을 쓰므로
    -- 시퀀스를 이 값 위로 밀어 둔다 — 그러지 않으면 다음 insert가 이 자리를 다시 찍어
    -- 유일 제약에 걸리고 **할 일 추가가 실패한다**(맨 아래로 k번 끌면 k번 연달아 실패한다).
    -- greatest로 감싸는 이유: 시퀀스가 이미 더 앞서 있으면(다른 기기가 그만큼 추가했으면)
    -- 뒤로 되돌리지 않아야 한다. nextval을 먼저 불러 읽는 것은 setval이 "다음에 줄 값"을
    -- 정하기 때문이다(currval은 이 세션에서 아직 발급받지 않았으면 쓸 수 없다).
    v_new_pos := v_after_pos + 1024;
    perform setval(
      'public.todos_position_seq',
      greatest(nextval('public.todos_position_seq'), v_new_pos / 1024)
    );
  elsif v_next_pos - v_after_pos >= 2 then
    v_new_pos := v_after_pos + (v_next_pos - v_after_pos) / 2;   -- 정수 나눗셈(내림)
  else
    -- 틈 고갈. 같은 틈에 열 번 남짓 연달아 끼워 넣으면 닿는다. 이 사용자의 목록을 **원하는 최종
    -- 순서 그대로** 1024 간격으로 다시 매긴다 — 상대 순서는 하나도 바뀌지 않고 값만 바뀐다.
    -- 유일 제약을 commit까지 미루는 이유: 한 문장 안에서 값을 돌려 끼우면 행별 즉시 검사가
    -- 헛되게 부딪힌다. (이 한 줄을 쓸 수 없는 환경이면 대안은 두 문장이다 —
    --  (1) 모든 행을 greatest(max, 행수*1024) - min + 1024 만큼 올려 기존·목표 값 위로 비켜 두고
    --  (2) 1024부터 다시 매긴다.)
    set constraints todos_user_position_key deferred;

    with ordered as (
      select id,
             row_number() over (
               -- 옮긴 행은 기준 행과 같은 키를 갖고 보조 키 1로 **바로 뒤**에 선다. 기준 행의
               -- 아래쪽 이웃은 position > v_after_pos라 자연히 그 다음이다.
               order by case when id = p_todo_id then v_after_pos else position end,
                        case when id = p_todo_id then 1 else 0 end
             ) as rn
      from public.todos
      where user_id = v_user
    )
    update public.todos t
    set position = ordered.rn * 1024
    from ordered
    where ordered.id = t.id;

    return;
  end if;

  update public.todos set position = v_new_pos where id = p_todo_id;
end;
$$;

-- Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 준다. 둘 다 회수한 뒤 부여한다.
revoke execute on function public.move_todo(uuid, uuid) from public, anon;
grant execute on function public.move_todo(uuid, uuid) to authenticated;

comment on function public.move_todo is
  '개인 투두 하나를 p_after_id 바로 아래로 옮긴다(p_after_id가 null이면 맨 위). 자리 값은 서버가 그 순간의 실제 이웃에서 만들고, 틈이 고갈되면 그 사용자의 목록을 다시 번호 매긴다.';
