-- 개인 투두의 기한(todo-due-date P0).
--
-- 선택 입력이라 nullable이고 기본값을 두지 않는다 — 기존 행은 전부 null(기한 없음)로 남는다.
-- 생성 시각으로 기한을 추정해 채우는 백필을 하지 않는다(spec "기존 할 일은 모두 기한 없는 상태").
--
-- 대결의 마감(battles.deadline_at, judge_deadline_at)과 아무 관계가 없다. 이 컬럼은
-- settle_expired_battles()·판정·점수·한도 어디에서도 읽히지 않고, 이 컬럼 때문에 생기는
-- cron·Edge Function·서버 발송 경로도 없다(spec "P1. 도메인 경계").
--
-- 인덱스를 함께 만들지 않는다: 쿼리는 지금처럼 where user_id = ? order by created_at 하나이고
-- 기한 순서는 서버가 아니라 Dart(sortedForList)가 만든다 — due_at으로 정렬·필터하는 SQL이 없다
-- (design 1.2). 정렬을 서버로 옮기게 되면 그때 (user_id, due_at) 인덱스를 추가한다.
--
-- RLS·트리거에 영향이 없다: 정책 4개는 모두 auth.uid() = user_id라는 행 조건식이라 컬럼 목록을
-- 갖지 않고, 테이블 단위 grant에는 새 컬럼이 자동으로 포함되며, todos_set_updated_at은 행 단위로
-- updated_at만 건드린다(design 1.3).
alter table public.todos
  add column due_at timestamptz;

comment on column public.todos.due_at is
  '개인 투두의 기한(UTC). null이면 기한 없음. 기한이 지나도 서버는 아무 일도 하지 않는다(자동 완료·삭제 없음).';
