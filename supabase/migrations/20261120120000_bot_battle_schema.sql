-- bot-battle 1단계: 봇 계정·주제 묶음·battles/battle_submissions 확장·봇전 점수표.
--
-- 근거: docs/specs/bot-battle/design.md §2(데이터 모델)·§3.5(점수)·§13(주제 8개)·§15(1단계),
--       docs/specs/bot-battle/spec.md "합격선", 오너 결정 1~6.
--
-- 핵심 규칙
--   - **봇전 1판이 일으키는 Gemini 호출은 0회다.** 그래서 봇전 기준은 AI가 만들지 않고 운영자가
--     미리 쓴 bot_battle_topics 행에서 복사한다. criteria_checks·ai_criteria_calls·criteria_cache에
--     행이 생기지 않는다(그 세 테이블은 이 파일에 등장하지 않는다).
--   - **봇은 등장인물이 아니라 시계다.** profiles 행 하나를 갖고, player_stats 행은 갖지 않으며,
--     deleted_at도 갖지 않는다(묘비로 보이면 안 된다).
--   - **사람 대결은 한 줄도 달라지지 않는다.** outcome_score_delta를 고치지 않고 봇전 전용 표를
--     따로 둔다. battles의 새 컬럼은 기본값 false이고 새 제약 세 개는 기존 행에서 모두 참이다.
--   - 이 단계만 적용된 상태에서는 봇전을 시작할 RPC도 화면도 없어 is_bot=true인 행이 생길 수 없다
--     (2단계가 start_bot_battle을 만든다).
--
-- 적용 전 확인(오너) — 아래 세 질의가 전부 0이어야 한다. bot_user_id()는 이 파일이 만들므로
-- 적용 전에는 리터럴로 본다.
--   select count(*) from public.battles
--     where opponent_id = '00000000-0000-0000-0000-00000000b07b';
--   select count(*) from public.battle_submissions where captured_at is null;
--   select count(*) from public.profiles
--     where id = '00000000-0000-0000-0000-00000000b07b';

-- ---------------------------------------------------------------------------
-- bot_user_id(): 봇의 id가 코드에 나타나는 유일한 자리
-- ---------------------------------------------------------------------------
-- seed 상수다. 비밀이 아니다 - 사용자는 이미 자기 봇전의 opponent_id를 읽는다.
--
-- authenticated에 EXECUTE를 주는 이유: 이 함수가 아래 CHECK 제약 식에 들어간다. 훗날 battles·
-- battle_submissions에 사용자 롤로 쓰는 경로가 생겼을 때 제약 평가가 권한 오류로 깨지지 않게
-- 한다(같은 이유로 is_criteria_list도 authenticated에서는 회수하지 않았다 - 20260916130000:37).
create function public.bot_user_id()
returns uuid
language sql
immutable
parallel safe
as $$ select '00000000-0000-0000-0000-00000000b07b'::uuid $$;

comment on function public.bot_user_id is
  '연습 봇의 고정 user id. 봇 uuid가 코드에 나타나는 유일한 자리다. 봇은 auth.users 행이 없어 '
  '로그인 경로가 존재하지 않는다. CHECK 제약 식에서 쓰므로 authenticated에도 EXECUTE를 준다.';

revoke execute on function public.bot_user_id() from public, anon;
grant execute on function public.bot_user_id() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 봇 profiles 행 (seed 1행)
-- ---------------------------------------------------------------------------
-- profiles.id의 auth.users FK는 2026-09-02에 끊겼다(20260902213000_delete_account.sql:18 -
-- 탈퇴 묘비를 남기기 위해). 그래서 auth 계정 없는 profiles 행이 구조적으로 가능하고, 평소 행
-- 생성을 담당하는 on_auth_user_created 트리거를 거치지 않고 seed가 직접 넣어도 제약이 없다.
--
-- player_stats 행을 **만들지 않는다**: 모든 사용자의 봇전이 한 봇에 쌓이므로 그 숫자에 뜻이 없고,
-- 상대 전적 자리에 봇의 수천 승이 뜨면 괴상하다(spec "부딪히는 곳 4"). handle_new_user 트리거는
-- 봇에 대해 돌지 않고, finalize_battle은 2단계에서 봇 참가자를 건너뛰게 고친다.
--   ** 앞으로 profiles를 훑어 다른 테이블 행을 만드는 마이그레이션을 쓸 때는
--      `and id <> public.bot_user_id()`를 넣을 것 ** (20260915120100의 player_stats 백필이
--      그런 모양이었다 - 그 백필이 지금 다시 돌면 봇에게 점수 행이 생긴다).
--
-- deleted_at은 null로 둔다. 묘비로 보이면 안 되고(spec 4번), get_player_card의 deleted 분기에도
-- 걸리지 않아야 한다. 이름(연습 봇)은 앞 두 글자가 역할을 말해 사람 닉네임으로 읽히지 않는다.
insert into public.profiles (id, display_name)
values (public.bot_user_id(), '연습 봇')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- bot_battle_topics: 운영자가 미리 쓰고 검수한 주제 묶음 (신규)
-- ---------------------------------------------------------------------------
-- 이 테이블이 "AI 호출 0회"를 가능하게 하는 장치다(spec P0-1). 봇전의 제목·최소 기준·기간은
-- 전부 여기서 나오고, 사용자가 제목을 쓰거나 기간을 고르는 경로는 없다.
--
-- type·superiority_criteria 칸을 두지 않는다: 봇전은 전부 speed이고 품질전 봇전은 성립하지
-- 않는다(spec "부딪히는 곳 2" - 봇에게는 비교할 사진이 없다). 칸을 두면 그것이 곧 범위 밖을 위한
-- 미래 대비 추상화다.
--
-- 기간이 주제에 붙는 이유: t_bot이 기간의 비율로 정해지므로 **기간을 길게 잡는 것이 곧 난이도를
-- 낮추는 것**이다. 기간 선택을 열면 난이도 선택 UI를 뒷문으로 들이게 된다(spec P0-1).
--
-- 사용자 FK가 없다. 그래서 CLAUDE.md의 "사용자 FK는 public.profiles" 규칙이 적용될 칸이 없다.
create table public.bot_battle_topics (
  id uuid primary key default gen_random_uuid(),
  title text not null
    constraint bot_battle_topics_title_check check (length(btrim(title)) between 1 and 60),
  min_criteria jsonb not null
    constraint bot_battle_topics_min_shape check (public.is_criteria_list(min_criteria)),
  duration_minutes integer not null
    constraint bot_battle_topics_duration_check check (duration_minutes between 1 and 10080),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

comment on table public.bot_battle_topics is
  '봇전(연습 대결) 주제 묶음. 운영자가 마이그레이션으로만 넣는다(사용자 제안·투표·운영 화면은 '
  '범위 밖). 전부 speed이고 우열 기준이 없다. ** RLS를 켜고 정책을 0개 두는 것이 정답이다 ** - '
  '"나중에 정책을 붙인다"가 아니다. 읽는 경로를 list_bot_battle_topics() 하나로 못박아 그 RPC가 '
  '남은 횟수까지 함께 내주게 한 것이고, criteria_cache와 같은 모양이다. 쓰기 경로는 '
  '마이그레이션뿐이라 insert/update/delete 정책도 두지 않는다.';
comment on column public.bot_battle_topics.min_criteria is
  '최소 기준(문자열 1~5개). 사람 대결 기준과 같은 모양이어야 화면이 같은 위젯으로 그리므로 '
  '기존 is_criteria_list를 그대로 재사용한다. start_bot_battle이 이 값을 battles.min_criteria로 '
  '복사한다(증서·캐시·임베딩을 거치지 않는다).';
comment on column public.bot_battle_topics.duration_minutes is
  '제출 창의 길이(분). 사용자가 고르지 않고 주제에 붙어 있다 - 기간을 길게 잡는 것이 곧 난이도를 '
  '낮추는 것이기 때문이다(t_bot이 기간의 비율로 정해진다).';
comment on column public.bot_battle_topics.active is
  '운영 규칙: ** 주제 행을 고치지 않고 교체한다. ** 문장을 바꾸려면 옛 행을 active=false로 '
  '내리고 새 행을 넣는다. 그러면 "사용자가 본 기준"과 "대결에 복사된 기준"이 어긋날 수 없어 '
  'criteria_version 같은 장치가 필요 없다.';
comment on column public.bot_battle_topics.sort_order is
  '주제 고르기 화면의 순서(작은 값이 위). 새 사용자가 가장 먼저 보는 카드를 운영자가 정하는 수단.';

alter table public.bot_battle_topics enable row level security;

-- 정책을 하나도 두지 않는다(위 테이블 주석의 근거). 기본 그랜트까지 함께 회수해 두 겹으로 막는다.
revoke all on table public.bot_battle_topics from anon, authenticated;

-- 인덱스를 두지 않는다. 10여 행이라 전체 스캔이 더 싸다.

-- ---------------------------------------------------------------------------
-- 초기 주제 8행 (design §13, 2026-11-20 오너 승인)
-- ---------------------------------------------------------------------------
-- 선정 기준 다섯을 전부 적용했다: ① 사진 한 장으로 완료가 보인다 ② 집이나 바로 근처에서 몇 분
-- 안에 ③ 도구·돈·타인 불필요 ④ 얼굴·타인·주소·차량 번호가 찍히기 쉬운 주제 제외 ⑤ 사진으로
-- 증명할 수 없는 종류(독서·명상·공부 시간) 제외.
--
-- 기준은 2개씩으로 맞췄다(1개는 "아무거나 한 장"에 가깝고 4~5개는 짧은 기간에 과하다).
-- 기간은 5·10·15분 세 종류다 - 1일·3일·7일 같은 긴 기간은 t_bot이 멀어져 사실상 무조건
-- 승리가 되므로 두지 않았다.
--
-- 집 안 정리가 여섯 개로 치우쳐 있다: 선정 기준 ①④⑤를 동시에 만족하는 집안일이 사실상
-- 정리·치우기 계열이다. 창문 열기(창밖에 간판·건물이 찍혀 위치가 드러난다), 산책·외출(얼굴·타인·
-- 차량 번호), 독서·스트레칭(사진으로 증명 불가)은 기준에 걸려 제외했다.
insert into public.bot_battle_topics (title, min_criteria, duration_minutes, sort_order)
values
  ('설거지하기',
   '["싱크대 안에 씻지 않은 그릇이나 컵이 보이지 않는다", "싱크대 바닥에 음식물 찌꺼기가 남아 있지 않다"]'::jsonb,
   10, 1),
  ('책상 정리하기',
   '["책상 위 물건이 치워져 상판이 드러나 있다", "컵·그릇·포장지 같은 쓰레기가 책상 위에 보이지 않는다"]'::jsonb,
   10, 2),
  ('쓰레기통 비우기',
   '["쓰레기통 안이 비어 있거나 새 봉투가 끼워져 있다", "쓰레기통 주변 바닥에 쓰레기가 떨어져 있지 않다"]'::jsonb,
   5, 3),
  ('이불 정리하기',
   '["이불이 펼쳐진 채 자리 위에 네모지게 정돈돼 있다", "베개가 이불 위쪽 제자리에 놓여 있다"]'::jsonb,
   5, 4),
  ('신발 정리하기',
   '["신발이 코를 같은 방향으로 두고 나란히 놓여 있다", "뒤집히거나 겹쳐 놓인 신발이 보이지 않는다"]'::jsonb,
   5, 5),
  ('물 한 컵 마시기',
   '["다 마신 빈 컵이나 빈 물병이 사진 한가운데에 보인다", "컵 안에 물이 남아 있지 않다"]'::jsonb,
   5, 6),
  ('빨래 개기',
   '["갠 옷가지가 세 벌 이상 쌓여 있다", "옷이 각각 반듯하게 접혀 모양이 흐트러지지 않았다"]'::jsonb,
   15, 7),
  ('방 바닥 치우기',
   '["바닥에 있던 물건이 치워져 바닥면이 드러나 있다", "옷·가방·쓰레기가 바닥에 보이지 않는다"]'::jsonb,
   15, 8);

-- ---------------------------------------------------------------------------
-- battles: is_bot·bot_topic_id
-- ---------------------------------------------------------------------------
-- t_bot(봇의 목표 시각)을 **여기에 두지 않는다.** 정책 "participants can view their battles"가
-- 행 전체를 내주고 RLS에는 컬럼을 가릴 수단이 없어 그 값이 그대로 샌다. t_bot은
-- battle_submissions의 봇 행(submitted_at)에 둔다 - 그 테이블의 select 정책이 "판정 창이
-- 열리거나 종결된 뒤에만 상대 행"이라는 정확히 필요한 시점 분기를 이미 갖고 있다(design §1.4).
alter table public.battles
  add column is_bot boolean not null default false,
  add column bot_topic_id uuid references public.bot_battle_topics (id);

-- 제약 셋이 함께 "봇전으로 위장하기"와 "사람 대결로 위장하기"를 양방향으로 막는다.
--   pair : 주제 없는 봇전도, 주제가 붙은 사람 대결도 없다
--   speed: 품질전 봇전은 성립하지 않는다(spec "부딪히는 곳 2")
--   opponent: 봇이 상대인데 is_bot이 false일 수 없고(봇전 아닌 척), is_bot인데 상대가 사람일
--             수도 없다(봇전 점수표로 사람 대결 치르기). opponent_id가 null인 모집 행은
--             양변이 모두 false로 통과한다 -> **status='pending'인 봇전 행은 존재할 수 없다.**
alter table public.battles
  add constraint battles_bot_topic_pair_check
    check ((bot_topic_id is not null) = is_bot),
  add constraint battles_bot_speed_only_check
    check (not is_bot or type = 'speed'),
  add constraint battles_bot_opponent_check
    check (is_bot = (opponent_id is not null and opponent_id = public.bot_user_id()));

comment on column public.battles.is_bot is
  '연습 봇과의 대결인지. 봇전은 모집(pending)을 거치지 않고 시작 즉시 active가 되며, judging을 '
  '거치지만 머무르지 않는다(판정 창이 열리는 순간 자동 승인으로 종결된다 - 판정 기한 24시간이 '
  '한 번도 걸리지 않는다). 점수는 bot_outcome_score_delta를 쓰고 승/패/무 카운터에는 들어가지 '
  '않는다. 클라이언트는 이 값 하나로 배지·분기를 고르므로 봇 uuid가 앱 코드에 들어가지 않는다.';
comment on column public.battles.bot_topic_id is
  '어느 주제로 시작했는지. 제목만으로는 교체된(active=false) 옛 주제와 구분되지 않는다. '
  'FK는 기본값(no action)이라 쓰인 주제를 실수로 지울 수 없다.';

comment on column public.battles.status is
  'pending(모집 중) -> active(매칭됨, 제출 창) -> judging(상호 판정 창, 두 유형 공통) -> '
  'finished(승자 있음) | draw | voided(불복·불일치 AI 재판정이 끝내 실패) | cancelled. '
  'disputed는 유료 재심용 개념으로만 남고 MVP의 어떤 함수도 이 값을 쓰지 않는다. '
  '봇전(is_bot)은 pending을 거치지 않고 active로 시작하며 judging에 머물지 않고, draw·voided에 '
  '도달하는 경로가 없다(봇 제출 행이 시작부터 있고 불복이라는 입력이 들어올 자리가 없다).';

-- cron(settle_due_bot_battles)이 훑는 자리와 하루 3회 계수가 전체 스캔을 하지 않게 조건부로 둔다.
create index battles_bot_active_idx
  on public.battles (started_at) where is_bot and status = 'active';
create index battles_bot_creator_started_idx
  on public.battles (creator_id, started_at) where is_bot;

-- ---------------------------------------------------------------------------
-- battle_participants: 봇전에서 has_submitted의 뜻이 달라진다 (주석만)
-- ---------------------------------------------------------------------------
-- 이 테이블은 상대 참가자도 모든 컬럼을 읽는다(테이블 주석의 불변식). 봇의 제출 행은 시작부터
-- 있지만 그 사실이 t_bot 전에 이 컬럼으로 새면 "봇이 제출했어요"가 보여 공개 범위가 깨진다.
-- 그래서 2단계의 open_judging_window가 **판정 창이 열릴 때** 이 값을 참으로 만든다.
comment on column public.battle_participants.has_submitted is
  '이 사람이 증거를 제출했는지. 시각·사진·통과 여부는 담지 않으므로 상대에게 보여도 된다. '
  '** 봇전(battles.is_bot)에서 봇 행의 뜻은 "제출 행이 있는가"가 아니라 "그 제출이 공개됐는가"다 ** '
  '- 봇의 제출 행은 대결이 시작될 때 이미 만들어지지만(제출 시각 = 봇의 목표 시각) 이 값은 '
  '판정 창이 열리는 순간에야 참이 된다. 시작 시점에 참으로 만들면 상대가 읽는 요약을 통해 '
  '"봇이 벌써 완료했다"가 목표 시각 전에 새어 나간다.';

-- ---------------------------------------------------------------------------
-- battle_submissions: 사진 없는 봇 제출
-- ---------------------------------------------------------------------------
-- 봇은 사진을 찍지 않으므로 **촬영 시각이 없다.** 아무 값이나 채워 넣는 것은 spec이 사진 자리에
-- 대해 금지한 것("없는 것을 있는 것처럼 꾸미지 않는다")을 데이터에서 하는 것이다.
--
-- "사람이 사진 없이 제출할 수 없다"의 보증 세 겹:
--   ① 사용자는 이 테이블에 쓸 수 없다(insert/update/delete 정책이 하나도 없다)
--   ② 유일한 사용자 경로 accept_submission이 p_object_path 빈 값과 p_captured_at is null을
--      각각 예외로 막는다(2단계에서도 그 두 줄을 그대로 둔다)
--   ③ 아래 CHECK가 captured_at is null을 봇 행으로 제한한다
--
-- object_path는 이미 nullable이다(탈퇴 시 null이 된다). 그래서 그 컬럼만으로는 봇 행을 식별할 수
-- 없다 - 식별은 언제나 user_id = bot_user_id()로 한다.
alter table public.battle_submissions
  alter column captured_at drop not null;

alter table public.battle_submissions
  add constraint battle_submissions_captured_at_check
    check (captured_at is not null or user_id = public.bot_user_id());

comment on column public.battle_submissions.captured_at is
  '앱이 보낸 촬영 시각. 거부 판단(대조)에만 쓰고 승부와 AI 전송에는 쓰지 않는다. '
  '** null은 연습 봇의 제출 행뿐이다 ** - 봇은 사진을 찍지 않아 촬영 시각이 없고, 위 CHECK가 '
  '그 예외를 봇 행으로 못박는다(사람의 사진 없는 제출을 막는 세 겹 중 하나).';

-- ---------------------------------------------------------------------------
-- bot_outcome_score_delta: 봇전 전용 점수표 (오너 결정 2·5)
-- ---------------------------------------------------------------------------
-- outcome_score_delta는 **손대지 않는다.** 사람 대결 점수(+3 / -1 / -3 / draw 양쪽 -1)는 한 줄도
-- 바뀌지 않는다.
--
-- 봇전은 승 +1, 그 밖의 패배·포기가 전부 -1이다(오너 결정 5 - 완료한 패배·완료 못 한 패배·포기를
-- 가르지 않는다). 수확(하루 3회 x +1 = +3)과 손실(-3)이 대칭이고 "작게 걸고 작게 받는다"로
-- 설명이 한 줄이다. 그 대가("걸어 놓고 안 해도 거의 손해가 없다")는 오너가 알고 고른 쪽이고,
-- 끝까지 하게 만드는 일은 N6(마감 임박) 알림이 맡는다.
--
-- draw에 -1을 주는 이유: draw는 봇전에서 도달하지 않는 값이지만(봇 제출 행이 시작부터 있고
-- t_bot < deadline_at이 불변식이다), finalize_battle이 greatest(v_old_score + v_delta, 0)을
-- 쓰므로 **delta가 null이면 점수가 0으로 날아간다.** 도달하지 않는 값이라도 null을 돌려주지
-- 않는다. 이 함수가 null을 돌려주는 경우는 outcome 자체가 잘못된 값일 때뿐이고, 그때는
-- finalize_battle의 모양 검사가 먼저 막는다.
create function public.bot_outcome_score_delta(p_outcome text)
returns integer
language sql
immutable
set search_path = public
as $$
  select case p_outcome
           when 'win' then 1
           when 'completed_loss' then -1
           when 'loss' then -1
           when 'forfeit' then -1
           when 'draw' then -1
           else null
         end
$$;

comment on function public.bot_outcome_score_delta is
  '봇전 outcome -> 점수 변화. win +1, 그 밖(completed_loss/loss/forfeit/draw) -1, 잘못된 값 null. '
  '하한 0은 finalize_battle이 적용한다. 사람 대결은 outcome_score_delta를 그대로 쓴다(이 함수가 '
  '그 표를 대체하지 않는다). 내부 전용.';

revoke execute on function public.bot_outcome_score_delta(text) from public, anon, authenticated;
