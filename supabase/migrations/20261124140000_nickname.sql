-- nickname 1단계(DB-A): 별명 규칙·무작위 별명·쓰기 경로를 한 함수 한 문으로 모은다.
--
-- 근거: docs/specs/nickname/design.md §1(데이터 모델)·§2(규칙)·§3(무작위 별명)·§4(쓰기 경로 닫기)·
--       §6(API 계약)·§12 1단계, docs/specs/nickname/spec.md 오너 결정 1~8(2026-11-24).
--
-- 핵심 규칙
--   - **규칙은 check_nickname() 한 함수에만 있다.** 쓰기 네 경로(관문 확정·프로필에서 바꾸기·새 계정의
--     기본 별명·기존 사용자 일괄 덮기)가 전부 이 함수를 지난다. 앱은 규칙을 재현하지 않는다.
--   - **쓰는 문은 하나다.** profiles의 UPDATE 정책을 없애고 테이블 쓰기 권한도 회수한다. 사용자가 이름을
--     바꾸는 길은 set_nickname() 하나이고, deleted_at(탈퇴 표시)을 바꾸는 사용자 경로는 없다.
--   - **단어표는 서버에만 있다.** 형용사·명사·예약어·금칙어 목록이 앱에 한 글자도 없다.
--   - **남에게 보이면 안 되는 상태는 profiles에 두지 않는다.** profiles는 로그인한 누구나 행 전체를
--     읽으므로, "확정했는가"·"서버가 덮었는가"는 본인만 RPC로 읽는 nickname_states에 둔다.
--   - 별명은 AI에 보내지 않는다(spec 결론 C). 이 파일의 어떤 함수도 Edge Function·AI 원장과 닿지 않는다.
--
-- 이 단계만 적용된 상태도 안전하다(design §12): 옛 앱은 관문이 없으니 그대로 돌고, 새 가입자는 무작위
-- 이름을 받고, 직접 쓰기는 이미 닫혀 있다. 기존 사용자의 이름을 덮는 것은 2단계(20261124140100)다.
--
-- 적용 전 확인(오너) — design §2.4·§2.5·§3.1 표 승인(2026-11-24 오너 결정 2로 승인됨).
-- 이 파일 맨 끝의 assert_nickname_pool_valid()가 단어표 1,600 조합이 전부 규칙을 통과하는지 적용 시점에
-- 확인한다. 하나라도 어긋나면 이 마이그레이션 전체가 되돌아간다(가입 시점에 실패하지 않게 하려는 것).

-- ---------------------------------------------------------------------------
-- 1. 테이블 세 개
-- ---------------------------------------------------------------------------

-- 1.1 nickname_states: 본인만 RPC로 읽는 관문 상태
create table public.nickname_states (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  confirmed_at timestamptz,
  reset_at timestamptz
);

comment on table public.nickname_states is
  '별명 관문 상태(본인만 get_my_nickname_state()로 읽는다). profiles에 두지 않는 이유: profiles는 '
  '로그인한 누구나 행 전체를 읽으므로 남의 별명 변경 시점이 보이게 된다(design 원칙 4). '
  '** RLS를 켜고 정책을 0개 두는 것이 정답이다 ** - 읽는 길은 get_my_nickname_state(), 쓰는 길은 '
  'handle_new_user·set_nickname·2단계 마이그레이션·delete_account뿐이고 전부 SECURITY DEFINER거나 '
  '마이그레이션이다. 봇·탈퇴 묘비는 행이 없다.';
comment on column public.nickname_states.confirmed_at is
  '사용자가 set_nickname으로 마지막에 확정한 시각. null이면 관문이 뜬다. 횟수 제한에 쓰지 않는다'
  '(오너 결정 7) - 바꿀 때마다 now()로 덮고 이력은 남기지 않는다.';
comment on column public.nickname_states.reset_at is
  '서버가 사용자 대신 이름을 덮은 시각(2단계 일괄 덮기). null이 아니면 관문에 "이름이 별명으로 '
  '바뀌었어요" 안내가 함께 뜬다. 원래 이름은 어디에도 보관하지 않는다(오너 결정 2).';

alter table public.nickname_states enable row level security;
revoke all on table public.nickname_states from anon, authenticated;

-- 1.2 nickname_words: 무작위 별명 단어표(형용사 + 명사)
-- 글자 수 상한 5 + 1(공백) + 4 = 10이라 어떤 조합도 길이 규칙(2~10자)을 넘을 수 없다.
create table public.nickname_words (
  kind text not null
    constraint nickname_words_kind_check check (kind in ('adjective', 'noun')),
  word text not null
    constraint nickname_words_word_check check (word ~ '^[가-힣]+$'),
  primary key (kind, word),
  constraint nickname_words_length_check check (
    (kind = 'adjective' and char_length(word) between 2 and 5)
    or (kind = 'noun' and char_length(word) between 1 and 4)
  )
);

comment on table public.nickname_words is
  '무작위 기본 별명(형용사 + 공백 + 명사)의 단어표. 운영자가 마이그레이션으로만 넣는다. '
  '** 운영 규칙: 이 테이블이나 nickname_blocked_terms를 바꾸는 마이그레이션은 마지막 줄에 '
  'select public.assert_nickname_pool_valid(); 를 둔다 ** - 새 금칙어가 기본 별명 조합과 겹치면 '
  '그 마이그레이션이 적용 시점에 실패하게 해, 가입(handle_new_user) 시점에 실패하지 않게 한다. '
  'RLS 켜고 정책 0개 + revoke all(bot_battle_topics와 같은 모양) - 앱에 내려보내지 않는다.';

alter table public.nickname_words enable row level security;
revoke all on table public.nickname_words from anon, authenticated;

-- 1.3 nickname_blocked_terms: 예약어·금칙어
-- 함수 안 배열이 아니라 테이블인 이유: 단어 하나를 더할 때마다 검사 함수 전체를 create or replace하지
-- 않고 마이그레이션 한 줄(insert/delete)로 끝내려는 것이다.
create table public.nickname_blocked_terms (
  term text primary key,
  category text not null
    constraint nickname_blocked_terms_category_check check (category in ('reserved', 'banned')),
  match text not null
    constraint nickname_blocked_terms_match_check check (match in ('exact', 'contains'))
);

comment on table public.nickname_blocked_terms is
  '별명 예약어(reserved: 시스템·화면이 쓰는 말, 운영·앱 사칭)와 금칙어(banned: 대놓고 하는 욕·혐오 표현). '
  '비교는 nickname_compare_key()로 양쪽 키를 만들어 한다(공백 제거·소문자·0→o, 1→i, l→i, 호환 자모 ㅣ→i·ㅇ→o). '
  '예약어는 거부할 때 걸린 term을 사용자에게 보여 주고, 금칙어는 보여 주지 않는다(design §2.6). '
  '** 운영 규칙: 이 테이블을 바꾸는 마이그레이션은 마지막 줄에 '
  'select public.assert_nickname_pool_valid(); 를 둔다 ** (nickname_words 주석과 같은 이유).';
comment on column public.nickname_blocked_terms.term is
  '보이는 모양(사용자에게 보여 줄 수 있는 형태). 비교 키는 저장하지 않고 그때그때 만든다.';

alter table public.nickname_blocked_terms enable row level security;
revoke all on table public.nickname_blocked_terms from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. seed (design §3.1·§2.4·§2.5 표 그대로, 2026-11-24 오너 결정 2로 승인)
-- ---------------------------------------------------------------------------

-- 2.1 형용사 40 (관형형, 2~5자, 외모·나이·성별·지능을 평가하는 말 없음)
insert into public.nickname_words (kind, word)
select 'adjective', w
from unnest(array[
  '부지런한', '느긋한', '용감한', '씩씩한', '재빠른',
  '꼼꼼한', '다정한', '명랑한', '차분한', '성실한',
  '엉뚱한', '졸린', '배고픈', '신나는', '반짝이는',
  '든든한', '상냥한', '날쌘', '끈질긴', '수줍은',
  '유쾌한', '침착한', '대담한', '슬기로운', '너그러운',
  '포근한', '말랑한', '동글동글한', '뿌듯한', '힘찬',
  '활기찬', '우아한', '의젓한', '당당한', '산뜻한',
  '늠름한', '듬직한', '해맑은', '행복한', '즐거운'
]) as t(w);

-- 2.2 명사 40 (동물, 1~4자. 욕으로 쓰이는 동물(개·돼지·쥐·닭·원숭이·벌레·뱀·하이에나)과
-- 속어로 읽히는 물개·하마는 뺐다)
insert into public.nickname_words (kind, word)
select 'noun', w
from unnest(array[
  '수달', '다람쥐', '고양이', '펭귄', '판다',
  '너구리', '고슴도치', '해달', '부엉이', '올빼미',
  '거북이', '토끼', '코알라', '기린', '사슴',
  '알파카', '비버', '햄스터', '호랑이', '사자',
  '돌고래', '고래', '해마', '오리', '참새',
  '까치', '앵무새', '두더지', '곰', '북극곰',
  '사막여우', '치타', '얼룩말', '카피바라', '코끼리',
  '낙타', '미어캣', '청설모', '강아지', '병아리'
]) as t(w);

-- 2.3 예약어 21 (design §2.4)
insert into public.nickname_blocked_terms (term, category, match)
values
  -- 화면이 사람 대신 쓰는 말(VS 인트로·대결 상세·이름을 못 읽었을 때의 대체 문구)
  ('나', 'reserved', 'exact'),
  ('상대', 'reserved', 'exact'),
  ('상대방', 'reserved', 'exact'),
  ('알 수 없음', 'reserved', 'exact'),
  -- 시스템이 화면에 대신 쓰는 이름(봇·탈퇴 묘비) 사칭
  ('연습봇', 'reserved', 'contains'),
  ('탈퇴', 'reserved', 'contains'),
  -- 운영·앱 사칭
  ('운영자', 'reserved', 'contains'),
  ('운영진', 'reserved', 'contains'),
  ('운영팀', 'reserved', 'contains'),
  ('관리자', 'reserved', 'contains'),
  ('고객센터', 'reserved', 'contains'),
  ('개발자', 'reserved', 'contains'),
  ('공식', 'reserved', 'contains'),
  ('시스템', 'reserved', 'contains'),
  ('투두두두', 'reserved', 'contains'),
  ('tododudu', 'reserved', 'contains'),
  ('todododo', 'reserved', 'contains'),
  ('admin', 'reserved', 'contains'),
  ('system', 'reserved', 'contains'),
  ('official', 'reserved', 'contains'),
  ('staff', 'reserved', 'contains');

-- 2.4 금칙어 42 (design §2.5, 전부 contains). 무해한 낱말이 자주 걸리는 말(새끼·보지·자지·미친·걸레·
-- ass·dick 등)은 일부러 뺐다. 알려진 오탐: 시발점(시발), Essex(sex).
insert into public.nickname_blocked_terms (term, category, match)
select w, 'banned', 'contains'
from unnest(array[
  -- 욕설(한글, 23)
  '씨발', '시발', '씨빨', '씨바', '병신', '븅신', '개새끼', '개색기', '개세끼', '좆',
  '존나', '지랄', '염병', '미친놈', '미친년', '썅', '니애미', '느금마', '엠창', '섹스',
  '창녀', '한남충', '김치녀',
  -- 초성 욕설(4)
  'ㅅㅂ', 'ㅆㅂ', 'ㅂㅅ', 'ㅄ',
  -- 혐오 표현(5)
  '틀딱', '맘충', '짱깨', '깜둥이', '쪽바리',
  -- 영문(10)
  'fuck', 'shit', 'bitch', 'cunt', 'nigger', 'nigga', 'faggot', 'asshole', 'sex', 'porn'
]) as t(w);

-- ---------------------------------------------------------------------------
-- 3. 내부 함수 5개 (security invoker, 사용자 롤에서 실행 권한 전부 회수)
-- ---------------------------------------------------------------------------
-- DEFINER가 아닌 이유(design §6.2): 이 함수들은 전부 DEFINER 함수(소유자 postgres) 안이나 마이그레이션·
-- 스모크(postgres)에서만 불린다. 그때 실행 주체가 이미 소유자다. 사용자 롤에 실행 권한이 없으므로
-- PostgREST로 직접 부를 수도 없다. 그래서 CLAUDE.md의 "DEFINER 첫 줄 로그인 가드"가 적용될 자리가 없다.

-- 3.1 정규화: NFC → 공백류를 공백 한 칸으로 → 앞뒤 공백 제거. 저장값은 이 결과다.
--   - NFC: 조합형 자모(U+1100대)로 친 "연습봇"을 완성형으로 합친다. 합쳐지지 않고 남는 조합형 자모는
--     check_nickname의 허용 문자 검사가 거부한다.
--   - 공백류: 공백(32)·탭(9)·줄바꿈(10)·CR(13)·NBSP(160)·전각 공백(12288). 눈에 공백으로 보이는 것만
--     공백으로 다룬다. 정규식 문자 클래스를 chr()로 만드는 이유는 파일 인코딩·이스케이프 해석에
--     기대지 않으려는 것이다.
create function public.normalize_nickname(p_raw text)
returns text
language sql
immutable
set search_path = public
as $$
  select btrim(
    regexp_replace(
      normalize(coalesce(p_raw, ''), NFC),
      '[' || chr(32) || chr(9) || chr(10) || chr(13) || chr(160) || chr(12288) || ']+',
      ' ',
      'g'
    ),
    ' '
  )
$$;

comment on function public.normalize_nickname(text) is
  '별명 정규화(NFC + 공백류를 한 칸으로 + 앞뒤 공백 제거). 내부 함수 - 사용자 롤은 실행할 수 없다. '
  'invoker인 이유는 DEFINER 함수·마이그레이션 안에서만 불리기 때문이다(design §6.2).';

-- 3.2 비교 키: 공백 전부 제거 → 소문자 → ASCII 혼동 문자 셋(0→o, 1→i, l→i)과 호환 자모 둘(ㅣ→i, ㅇ→o) 접기. 자모로 영문 예약어를 흉내 내는 `ADMㅣN`·`TㅇDㅇDUDU`를 막는다(리뷰 경고 3).
--   예약어·금칙어 쪽 키도 같은 함수로 만들어 비교하므로 양쪽이 어긋나지 않는다. 비교에만 쓰고 저장하지
--   않는다. 한글의 비슷한 글자는 접지 않는다(spec 트레이드오프가 받아들인 공백).
create function public.nickname_compare_key(p_normalized text)
returns text
language sql
immutable
set search_path = public
as $$
  select translate(lower(replace(coalesce(p_normalized, ''), ' ', '')), '01lㅣㅇ', 'oiiio')
$$;

comment on function public.nickname_compare_key(text) is
  '별명 비교 키(공백 제거·소문자·0→o 1→i l→i ㅣ→i ㅇ→o). 예약어·금칙어 비교에만 쓰고 저장하지 않는다. 내부 함수.';

-- 3.3 검사: 정규화 뒤 아래를 순서대로 보고 처음 걸린 것 하나를 돌려준다. 다 통과하면 code는 null.
--   1 길이 2~10(단어 사이 공백 포함)            -> NICKNAME_LENGTH
--   2 허용 문자(완성형 한글 U+AC00-D7A3, 호환 자모 U+3131-3163, ASCII 영문·숫자, 단어 사이 공백 한 칸)
--                                               -> NICKNAME_CHARS
--   3 예약어(exact는 키가 같음, contains는 포함) -> NICKNAME_RESERVED, term = 걸린 term(보이는 모양)
--   4 금칙어(같은 방식)                          -> NICKNAME_BANNED, term = null(욕설을 되돌려 보여 주지 않는다)
--   허용 목록 하나로 보이지 않는 문자(U+200B·200C·200D·2060·FEFF·3164·115F·1160·FFA0), 조합형 자모,
--   이모지, 전각 영문, 특수문자(@ . _ - ★)가 전부 2번에서 거부된다. 그래서 이메일·웹 주소 모양은
--   성립하지 않는다. 휴대폰 번호(11자리)는 1번에서 거부된다.
--   여러 term이 걸리면 term 오름차순(코드 포인트, collate "C") 첫 행이다.
create function public.check_nickname(
  p_raw text,
  out normalized text,
  out code text,
  out term text
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_key text;
begin
  normalized := public.normalize_nickname(p_raw);

  if char_length(normalized) not between 2 and 10 then
    code := 'NICKNAME_LENGTH';
    return;
  end if;

  if normalized !~ '^[가-힣ㄱ-ㅣA-Za-z0-9]+( [가-힣ㄱ-ㅣA-Za-z0-9]+)*$' then
    code := 'NICKNAME_CHARS';
    return;
  end if;

  v_key := public.nickname_compare_key(normalized);

  select b.term into term
  from public.nickname_blocked_terms b
  where b.category = 'reserved'
    and (
      (b.match = 'exact' and public.nickname_compare_key(b.term) = v_key)
      or (b.match = 'contains' and strpos(v_key, public.nickname_compare_key(b.term)) > 0)
    )
  order by b.term collate "C"
  limit 1;
  if found then
    code := 'NICKNAME_RESERVED';
    return;
  end if;

  perform 1
  from public.nickname_blocked_terms b
  where b.category = 'banned'
    and (
      (b.match = 'exact' and public.nickname_compare_key(b.term) = v_key)
      or (b.match = 'contains' and strpos(v_key, public.nickname_compare_key(b.term)) > 0)
    );
  if found then
    code := 'NICKNAME_BANNED';
    term := null;
    return;
  end if;
end;
$$;

comment on function public.check_nickname(text) is
  '별명 규칙의 유일한 자리. (normalized, code, term)을 돌려주고 통과하면 code가 null이다. '
  'set_nickname·random_nickname·assert_nickname_pool_valid가 부른다. 내부 함수 - 사용자 롤은 실행할 수 없다.';

-- 3.4 무작위 별명: 형용사 + 공백 + 명사. 결과는 check_nickname을 반드시 통과한다.
--   "아무도 쓰지 않는 조합 먼저"는 강제가 아니라 선호다(중복 허용, 오너 결정 5). 사용자 약 1,000명까지는
--   20번 모두 쓰인 조합만 뽑힐 확률이 사실상 0이다(design §3.2). 숫자를 붙이지 않는다(번호표처럼 읽힌다).
--   마지막 raise는 단어표가 비었을 때만 닿는다 - 이 함수가 던지면 가입 자체가 실패하므로(handle_new_user)
--   그 상태를 마이그레이션 시점에 assert_nickname_pool_valid()로 막는다.
create function public.random_nickname()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_candidate text;
  v_fallback text;
begin
  for i in 1..20 loop
    select a.word || ' ' || n.word into v_candidate
    from (select w.word from public.nickname_words w where w.kind = 'adjective' order by random() limit 1) a,
         (select w.word from public.nickname_words w where w.kind = 'noun' order by random() limit 1) n;

    exit when v_candidate is null;  -- 단어표가 비었다
    continue when (public.check_nickname(v_candidate)).code is not null;  -- 규칙에 안 맞는 조합은 버린다

    v_fallback := coalesce(v_fallback, v_candidate);
    if not exists (select 1 from public.profiles p where p.display_name = v_candidate) then
      return v_candidate;  -- 아무도 쓰지 않는 조합을 먼저 고른다
    end if;
  end loop;

  if v_fallback is not null then
    return v_fallback;  -- 겹쳐도 된다(오너 결정 5)
  end if;

  raise exception using message = '무작위 별명을 만들지 못했습니다.', hint = 'NICKNAME_POOL_EMPTY';
end;
$$;

comment on function public.random_nickname() is
  '무작위 기본 별명(형용사 + 공백 + 명사). check_nickname을 반드시 통과하고, 쓰이지 않은 조합을 먼저 고른다. '
  'handle_new_user·suggest_nickname·2단계 일괄 덮기가 부른다. 내부 함수 - 사용자 롤은 실행할 수 없다.';

-- 3.5 풀 검증: 형용사·명사가 각각 1개 이상이고, 모든 조합이 check_nickname을 통과하는지 본다.
--   실패하면 실패한 조합 최대 10개를 메시지에 담아 raise한다. 이 파일과, 앞으로 nickname_words·
--   nickname_blocked_terms를 고치는 마이그레이션의 마지막 줄에서 부른다.
create function public.assert_nickname_pool_valid()
returns void
language plpgsql
volatile
set search_path = public
as $$
declare
  v_adjectives integer;
  v_nouns integer;
  v_bad_count integer;
  v_bad_sample text;
begin
  select count(*) filter (where w.kind = 'adjective'),
         count(*) filter (where w.kind = 'noun')
  into v_adjectives, v_nouns
  from public.nickname_words w;

  if v_adjectives = 0 or v_nouns = 0 then
    raise exception '별명 단어표가 비었습니다(형용사 %개, 명사 %개).', v_adjectives, v_nouns;
  end if;

  select count(*),
         string_agg(x.candidate || '(' || x.code || ')', ', ' order by x.candidate) filter (where x.rn <= 10)
  into v_bad_count, v_bad_sample
  from (
    select c.candidate, c.code, row_number() over (order by c.candidate) as rn
    from (
      select a.word || ' ' || n.word as candidate,
             (public.check_nickname(a.word || ' ' || n.word)).code as code
      from public.nickname_words a
      cross join public.nickname_words n
      where a.kind = 'adjective'
        and n.kind = 'noun'
    ) c
    where c.code is not null
  ) x;

  if v_bad_count > 0 then
    raise exception '규칙에 걸리는 기본 별명 조합이 %개 있습니다: %', v_bad_count, v_bad_sample;
  end if;
end;
$$;

comment on function public.assert_nickname_pool_valid() is
  '단어표 전 조합이 별명 규칙을 통과하는지 확인하고, 아니면 raise한다. 단어표·예약어·금칙어를 바꾸는 '
  '마이그레이션의 마지막 줄에서 부른다. 내부 함수 - 사용자 롤은 실행할 수 없다.';

revoke execute on function public.normalize_nickname(text) from public, anon, authenticated;
revoke execute on function public.nickname_compare_key(text) from public, anon, authenticated;
revoke execute on function public.check_nickname(text) from public, anon, authenticated;
revoke execute on function public.random_nickname() from public, anon, authenticated;
revoke execute on function public.assert_nickname_pool_valid() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. 사용자 RPC 3개 (security definer, 첫 줄 로그인 가드, public·anon 회수 + authenticated 허용)
-- ---------------------------------------------------------------------------
-- 셋 다 탈퇴 계정을 거부한다(ACCOUNT_DELETED): auth.users가 지워진 뒤에도 이미 발급된 JWT는 만료(최대
-- 1시간) 전까지 유효하다. 그 토큰으로 묘비 이름을 바꾸는 길을 막는다(design §6.1).

-- 4.1 내 관문 상태. 상태 행이 없으면 confirmed=false, was_reset=false(2단계 전의 기존 사용자, 또는 예상 밖).
create function public.get_my_nickname_state()
returns jsonb
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_display_name text;
  v_deleted_at timestamptz;
  v_confirmed_at timestamptz;
  v_reset_at timestamptz;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select p.display_name, p.deleted_at into v_display_name, v_deleted_at
  from public.profiles p
  where p.id = v_user_id;
  if not found or v_deleted_at is not null then
    raise exception using message = '탈퇴한 계정입니다.', hint = 'ACCOUNT_DELETED';
  end if;

  select s.confirmed_at, s.reset_at into v_confirmed_at, v_reset_at
  from public.nickname_states s
  where s.user_id = v_user_id;

  return jsonb_build_object(
    'nickname', v_display_name,
    'confirmed', v_confirmed_at is not null,
    'was_reset', v_reset_at is not null
  );
end;
$$;

comment on function public.get_my_nickname_state() is
  '내 별명 관문 상태 {nickname, confirmed, was_reset}. 앱이 켜질 때 한 번 부른다. 실패하면 앱은 관문을 '
  '통과시킨다(design 결정 1의 (a)) - 노출은 서버의 기본 별명·일괄 덮기가 이미 끊었기 때문이다.';

-- 4.2 별명 확정·바꾸기(관문과 프로필이 같은 RPC). 원문을 그대로 받아 서버가 정규화한다.
--   - 본인 행만 고친다: 대상 id를 받는 인자가 없고 where id = auth.uid()다.
--   - 같은 이름으로 다시 확정해도 성공한다(멱등). 중복 검사도 횟수 제한도 없다(오너 결정 5·7).
--   - 예약어로 거부할 때만 detail에 걸린 term(보이는 모양)을 싣는다. 앱은 PostgrestException.details로 읽는다.
--     금칙어는 term을 싣지 않는다(욕설을 화면에 되돌려 보여 주지 않는다, design §2.6).
--   - 메시지는 로그용이다. 화면 문구는 앱이 hint 코드로 고른다.
create function public.set_nickname(p_nickname text)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_deleted_at timestamptz;
  v_check record;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select p.deleted_at into v_deleted_at
  from public.profiles p
  where p.id = v_user_id
  for update;
  if not found or v_deleted_at is not null then
    raise exception using message = '탈퇴한 계정입니다.', hint = 'ACCOUNT_DELETED';
  end if;

  select c.normalized, c.code, c.term into v_check
  from public.check_nickname(p_nickname) c;

  if v_check.code = 'NICKNAME_RESERVED' then
    raise exception using
      message = '앱이나 운영자가 쓰는 말이 들어 있어 쓸 수 없는 별명입니다.',
      hint = 'NICKNAME_RESERVED',
      detail = coalesce(v_check.term, '');
  elsif v_check.code = 'NICKNAME_LENGTH' then
    raise exception using message = '별명은 2~10자여야 합니다.', hint = 'NICKNAME_LENGTH';
  elsif v_check.code = 'NICKNAME_CHARS' then
    raise exception using
      message = '별명에는 한글·영문·숫자와 단어 사이 공백 한 칸만 쓸 수 있습니다.',
      hint = 'NICKNAME_CHARS';
  elsif v_check.code = 'NICKNAME_BANNED' then
    raise exception using message = '쓸 수 없는 말이 들어 있습니다.', hint = 'NICKNAME_BANNED';
  elsif v_check.code is not null then
    -- check_nickname이 새 코드를 돌려주게 되면 여기서 조용히 통과하지 않게 막는다.
    raise exception using message = '쓸 수 없는 별명입니다.', hint = v_check.code;
  end if;

  update public.profiles
  set display_name = v_check.normalized
  where id = v_user_id;

  insert into public.nickname_states (user_id, confirmed_at)
  values (v_user_id, now())
  on conflict (user_id) do update set confirmed_at = excluded.confirmed_at;

  return v_check.normalized;
end;
$$;

comment on function public.set_nickname(text) is
  '내 별명을 확정하거나 바꾼다(관문과 프로필이 같은 RPC). 사용자가 이름을 바꾸는 유일한 길이다. '
  '저장된 정규화 값을 돌려준다. 거부 hint: ACCOUNT_DELETED / NICKNAME_LENGTH / NICKNAME_CHARS / '
  'NICKNAME_RESERVED(detail = 걸린 예약어) / NICKNAME_BANNED.';

-- 4.3 다른 별명 추천받기(P1-1). 아무것도 쓰지 않는다. 내 지금 이름도 "쓰이는 조합"에 들어가므로 대개
--   다른 이름이 나온다.
create function public.suggest_nickname()
returns text
language plpgsql
volatile
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  perform 1
  from public.profiles p
  where p.id = v_user_id
    and p.deleted_at is null;
  if not found then
    raise exception using message = '탈퇴한 계정입니다.', hint = 'ACCOUNT_DELETED';
  end if;

  return public.random_nickname();
end;
$$;

comment on function public.suggest_nickname() is
  '무작위 별명 하나를 돌려준다(아무것도 쓰지 않는다). 관문의 "다른 별명 추천받기" 버튼이 부른다.';

-- Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 주므로 revoke를 함께 쓴다(CLAUDE.md).
revoke execute on function public.get_my_nickname_state() from public, anon;
grant execute on function public.get_my_nickname_state() to authenticated;
revoke execute on function public.set_nickname(text) from public, anon;
grant execute on function public.set_nickname(text) to authenticated;
revoke execute on function public.suggest_nickname() from public, anon;
grant execute on function public.suggest_nickname() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. handle_new_user: 기본 이름을 무작위 별명으로 (P0-1)
-- ---------------------------------------------------------------------------
-- **20260915120100_ai_judge_schema.sql:171의 정의(가장 늦은 정의)가 기준이다.** 바뀐 것은 둘이다.
--   - display_name을 public.random_nickname()으로 채운다. raw_user_meta_data·email을 더 이상 읽지 않는다
--     - 실명·이메일·외부 서비스 닉네임이 기본 이름이 될 길이 없다. 카카오 로그인이 들어와도 같은 트리거를
--     지나므로 카카오 닉네임이 기본값이 될 길도 없다(spec "다른 기능과의 관계").
--   - nickname_states 행을 (id, null, null)로 만든다 - 새 사용자는 첫 실행에 관문을 본다.
-- player_stats 행은 그대로 만든다.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, public.random_nickname());

  insert into public.player_stats (user_id) values (new.id);

  insert into public.nickname_states (user_id) values (new.id);

  return new;
end;
$$;

-- create or replace는 권한을 유지하지만 트리거 전용 함수라는 점을 한 번 더 못박는다.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. delete_account: nickname_states 한 줄 추가
-- ---------------------------------------------------------------------------
-- **20261116120000_notification_dismiss.sql:213의 정의(가장 늦은 정의)를 그대로 복사하고 7번 단계 끝에
-- 한 줄만 끼워 넣었다.** 열 번 넘게 재정의된 함수라 옛 정의를 베끼면 기준 증서·동의 기록·알림 토큰·
-- 읽음 시각·치운 기록 삭제가 조용히 되살아나거나 사라진다. 인자 없는 시그니처는 그대로이고 create or
-- replace라 GRANT도 그대로 남는다. 다른 동작은 한 줄도 바꾸지 않았다.
--
-- 왜 cascade에 맡기지 않는가: nickname_states.user_id FK는 public.profiles를 가리키는데 탈퇴는 profiles
-- 행을 "탈퇴한 사용자" 묘비로 **남기므로** cascade가 돌지 않는다(notification_dismissals와 같은 이유).
-- 묘비의 별명은 8번 단계가 "탈퇴한 사용자"로 바꾼다 - 시스템 이름이라 사용자 규칙(check_nickname) 밖이다.
create or replace function public.delete_account()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_cancelled_ids uuid[];
  v_cancelled record;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 1. 끝나지 않은 대결은 승자·점수 변화 없이 취소한다. 속도전에서 이미 통과했어도 취소다(결정 42).
  with cancelled as (
    update public.battles
    set status = 'cancelled', finished_at = now()
    where status in ('pending', 'active', 'judging')
      and (creator_id = v_user_id or opponent_id = v_user_id)
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_cancelled_ids from cancelled;

  -- N5. 남은 상대에게만. 상대가 없는 pending 모집은 알릴 사람이 없다(other_id가 null).
  -- 탈퇴한 사람의 이름은 담지 않는다. 한도가 없어졌으므로 "한도가 돌아왔다"는 말도 하지 않는다.
  for v_cancelled in
    select b.id,
           b.title,
           case when b.creator_id = v_user_id then b.opponent_id else b.creator_id end as other_id
    from public.battles b
    where b.id = any (v_cancelled_ids)
  loop
    perform public.enqueue_notification(
      v_cancelled.other_id,
      'cancelled',
      v_cancelled.id,
      'cancelled:' || v_cancelled.id::text,
      jsonb_build_object('title', v_cancelled.title)
    );
  end loop;

  -- 판정 대기 중이던 AI 재판정 잡. 대결이 취소됐으므로 판정할 것이 없다.
  delete from public.ai_judgment_jobs where battle_id = any (v_cancelled_ids);

  -- 2. 개인 투두.
  delete from public.todos where user_id = v_user_id;

  -- 3. 증거 사진 경로는 개인 데이터라 끊는다. 사진 파일은 앱이 이 RPC 직전에 Storage API로 지운다.
  --    제출 행 자체와 사유·시각은 남은 상대의 전적을 설명하는 판정 기록이라 남긴다.
  update public.battle_submissions
  set object_path = null
  where user_id = v_user_id;

  -- 4. 점수. 묘비 사용자의 점수는 공개 대상이 아니다.
  delete from public.player_stats where user_id = v_user_id;

  -- 5. 기준 증서와 호출 원장. 대결이 성립하기 전의 초안이라 보존할 이유가 없다.
  delete from public.criteria_checks where user_id = v_user_id;
  delete from public.ai_criteria_calls where user_id = v_user_id;

  -- 6. 동의·철회 기록. 탈퇴 후에는 남기지 않는다(decisions 68).
  delete from public.ai_consent_events where user_id = v_user_id;
  delete from public.ai_consents where user_id = v_user_id;

  -- 7. 알림 토큰과 내가 받을 알림. 개인정보처리방침의 "탈퇴 시 삭제"와 맞춘다.
  --    내가 수신자인 행만 지운다 - 상대가 받을 알림(방금 적재한 N5 포함)은 상대의 기록이다.
  delete from public.device_push_tokens where user_id = v_user_id;
  delete from public.notification_outbox where recipient_id = v_user_id;
  --    알림함 읽음 시각도 함께. FK가 profiles라 묘비가 남는 탈퇴에서는 cascade가 돌지 않는다.
  delete from public.notification_reads where user_id = v_user_id;
  --    치운 기록도 함께(치움은 계정의 값이다).
  delete from public.notification_dismissals where user_id = v_user_id;
  --    별명 관문 상태도 함께(nickname 2026-11-24). FK가 profiles라 cascade가 돌지 않는다.
  delete from public.nickname_states where user_id = v_user_id;

  -- 8. 묘비화.
  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 9. 실제 계정 삭제. 0행이면 "데이터만 지워지고 계정은 살아있는" 상태를 막기 위해 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. profiles 쓰기 경로 닫기 (P0-5, design §4)
-- ---------------------------------------------------------------------------
-- "자기 프로필 행은 자기가 고칠 수 있다"(컬럼 제한 없음)가 열려 있어, 앱을 거치지 않고 API를 직접 부르면
-- 이름을 길이·내용 제한 없이 바꾸고 deleted_at(탈퇴 표시)까지 바꿀 수 있었다(2026-11-24 보안 점검).
-- 앱은 이 정책을 한 번도 쓰지 않는다(lib/**의 profiles 접근은 select 세 곳뿐, Edge는 0곳). 서버에서
-- profiles를 고치는 delete_account·handle_new_user는 SECURITY DEFINER(소유자 기준)라 영향이 없다.
drop policy if exists "users can update their own profile" on public.profiles;

-- 두 겹째: 정책이 다시 생겨도 테이블 권한이 없으면 쓰기가 안 된다. insert·delete 정책은 원래 없다.
-- select 정책("profiles are viewable by any authenticated user")과 select 권한은 그대로 둔다(spec P0-5) -
-- 모집 목록·상대 카드·옛 앱의 select()가 그대로 동작해야 한다.
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

-- 정책 이름이 예상과 달라 drop이 아무것도 지우지 않았다면 여기서 멈춘다(조용히 문이 열린 채 남지 않게).
do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and cmd <> 'SELECT'
  ) then
    raise exception 'profiles에 select가 아닌 정책이 남아 있습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 8. 단어표 검증 (마지막 줄 - nickname_words 주석의 운영 규칙)
-- ---------------------------------------------------------------------------
select public.assert_nickname_pool_valid();
