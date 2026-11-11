-- 판정 기준 캐시(criteria-cache P0·P1).
--
-- 근거: docs/specs/criteria-cache/spec.md(2026-11-11 오너 승인)와 같은 폴더 design.md·plan.md.
--
-- 무엇인가: **기준 생성 AI 호출 앞에 끼우는 조회 한 단계**다. 제목을 임베딩해 뜻이 가까운 주제의
-- AI 원본 기준이 이미 있으면 그것으로 증서를 만들고 Gemini 생성 호출을 하지 않는다.
-- 판정(1차 상호 판정 -> 2차 AI 재판정)·상태 전이·승부·점수·마감·정산에는 한 줄도 닿지 않는다.
--
-- 핵심 규칙
--   - 이 테이블에는 **사용자 식별 정보가 없다**(user_id도 battle_id도 없다). 그래서 개인 데이터가
--     아니고 탈퇴와 무관하게 남는다(오너 결정 3). delete_account()는 이 테이블을 건드리지 않는다.
--   - **AI 원본만 들어온다.** 사용자가 손으로 고친 기준(criteria_checks의 action='check')은 적재
--     경로가 아예 없다 - "무조건 합격시켜라" 같은 문장이 캐시를 타고 전파되는 길을 만들지 않는다.
--   - 조회 대상은 **지금의 생성 모델/프롬프트 버전 + 지금의 임베딩 모델/작업유형/차원**으로 만든
--     행뿐이다. 버전이 바뀌면 옛 행은 지우지 않고 조회에서만 빠진다(끝난 대결의 기준 설명 자료).
--   - 적중은 하루 10회 한도를 소모하지 않는다. 그래서 적중 경로는 ai_criteria_calls에
--     **아무것도 쓰지 않는다**(원장의 뜻을 "AI에게 기준을 물은 횟수"로 유지한다).
--
-- 기존 객체를 하나도 고치지 않는다. begin/finish/fail_criteria_call, create_battle,
-- update_battle_criteria, get_my_limits, delete_account, criteria_checks·ai_criteria_calls의
-- 스키마와 RLS가 그대로다. 되돌리려면 이 파일이 만든 것(테이블 1 + 함수 4)만 drop하면 된다.
--
-- **교차 검산식**(한 컬럼을 두 경로가 채우므로 숫자로 맞춰 본다): 이제 criteria_checks를
-- finish_criteria_call(미적중)과 issue_cached_criteria_check(적중) **둘이** 채운다. 적중 증서에만
-- ai_model에 '/cache' 꼬리가 붙으므로 아래 식이 항상 성립해야 한다.
--   select count(*) from public.criteria_checks                                          -- 전체 증서
--     = (select count(*) from public.ai_criteria_calls where status = 'succeeded')       -- 미적중분
--     + (select count(*) from public.criteria_checks where ai_model like '%/cache');     -- 적중분
-- 어긋나면 어느 경로가 샜는지(적중이 원장을 건드렸는지, 꼬리 없이 증서가 생겼는지) 숫자로 드러난다.
--
-- **적용 순서: 이 파일 -> Edge Function 배포. 순서를 지켜야 한다.**
-- 반대로 하면(Edge를 먼저 배포하면) **모든 사용자의 generate가 500으로 끝난다.** 네 함수 중
-- assert_criteria_consent는 try/catch 밖의 **관문**이라, 함수가 없을 때의 오류에는 hint가 없어
-- codeFromHint가 null이 되고 Edge가 SERVER_ERROR(500)로 응답한다(PostgREST 스키마 캐시가 늦게
-- 갱신되는 동안에도 같다). 관문이 fail-closed인 것은 맞는 선택이다 - 동의 확인이 조용히 통과되는
-- 쪽이 훨씬 비싸다.
-- "실패가 캐시 미적중과 결과가 같다"(design 원칙 6)는 **나머지 셋에만** 적용된다
-- (lookup_criteria_cache / put_criteria_cache / issue_cached_criteria_check).

-- ---------------------------------------------------------------------------
-- 0) pgvector
-- ---------------------------------------------------------------------------
-- Supabase의 관례대로 extensions 스키마에 둔다(public을 확장 타입으로 더럽히지 않는다).
-- 아래 함수들이 set search_path = public, extensions로 선언되는 이유가 이것이다 - 벡터 타입과
-- <=> 연산자가 그 스키마에 있다. search_path에서 extensions를 빼면 함수가 깨진다.
create extension if not exists vector with schema extensions;

-- ---------------------------------------------------------------------------
-- 1) 캐시 테이블
-- ---------------------------------------------------------------------------
create table public.criteria_cache (
  id uuid primary key default gen_random_uuid(),
  -- 유형이 캐시 키에 들어간다(spec P0). 품질전은 우열 기준이 있어야 하고 속도전은 없어야 하며,
  -- 최소 기준의 뜻도 다르다(통과선 vs 참가선). 섞으면 증서 제약에서 깨지거나 뜻이 틀어진다.
  type text not null
    constraint criteria_cache_type_check check (type in ('speed', 'quality')),
  -- 정규화된 제목. **조회 키이고 진단 자료다.** 사용자에게 보여 주지 않으며, 조회 함수는 이 값을
  -- 반환값에 담지 않는다(남의 제목이 내 화면에 가는 경로를 반환 모양으로 막는다).
  title_norm text not null
    constraint criteria_cache_title_check check (length(title_norm) between 1 and 60),
  provable boolean not null,
  min_criteria jsonb not null default '[]'::jsonb,
  superiority_criteria jsonb,
  -- AI가 쓴 차단 사유 원문. **오너 진단용으로만 남긴다.** 다른 제목에 붙으면 틀린 설명이 되므로
  -- 적중 증서에는 이 값을 복사하지 않고 제목과 무관한 고정 문장을 쓴다(issue_cached_criteria_check).
  block_reason text,
  -- 'gemini-2.5-flash/p1' 형태. criteria_checks.ai_model과 같은 표기를 쓴다.
  ai_model text not null,
  -- 'gemini-embedding-001/SEMANTIC_SIMILARITY/768' 형태. 모델·작업유형·차원이 모두 벡터 공간을
  -- 바꾸므로 셋을 한 키로 묶는다. 서로 다른 공간의 벡터를 비교한 유사도는 아무 뜻이 없다.
  embedding_model text not null,
  -- L2 정규화된 제목 임베딩. 코사인 거리(<=>)로 비교한다.
  embedding extensions.vector(768) not null,
  created_at timestamptz not null default now(),
  -- 아래 네 제약은 criteria_checks의 것과 **같은 모양**이다. 캐시 행이 언제나 유효한 증서가 될 수
  -- 있음을 DB가 보장한다(한쪽만 바뀌면 적중이 증서 insert에서 깨진다).
  constraint criteria_cache_min_shape
    check (not provable or public.is_criteria_list(min_criteria)),
  constraint criteria_cache_superiority_shape
    check (superiority_criteria is null or public.is_criteria_list(superiority_criteria)),
  constraint criteria_cache_superiority_by_type
    check (not provable or ((type = 'quality') = (superiority_criteria is not null))),
  constraint criteria_cache_block_reason
    check (provable or (block_reason is not null and length(btrim(block_reason)) > 0))
);

comment on table public.criteria_cache is
  'AI가 만든 판정 기준의 재사용 저장소. 사용자 식별 정보가 없어 개인 데이터가 아니며 탈퇴와 '
  '무관하게 남는다. AI 원본만 들어오고 사용자가 고친 기준은 들어오지 않는다.';
comment on column public.criteria_cache.title_norm is
  '정규화된 제목(앞뒤·중복 공백 정리, 소문자화, NFC). 조회 키와 진단 자료이며 사용자에게 보여 주지 않는다.';
comment on column public.criteria_cache.block_reason is
  'AI가 쓴 차단 사유 원문. 진단용이다 - 다른 제목에 붙으면 틀린 설명이 되므로 증서로 복사하지 않는다.';
comment on column public.criteria_cache.embedding is
  'L2 정규화된 제목 임베딩(768차원). embedding_model이 가리키는 공간의 벡터끼리만 비교한다.';

-- 조회 두 경로가 함께 쓰는 인덱스. 앞의 세 칸이 버전 대조 필터이고, title_norm·created_at이
-- 정규화 일치 경로의 "가장 최근 하나"를 바로 집는다. 벡터 경로는 앞 세 칸으로 후보를 좁힌 뒤
-- 순차 비교한다 - **ANN 인덱스(ivfflat·hnsw)를 만들지 않는다.**
--   이유: (1) 지금 행 수는 0이고 배포 후에도 수백 규모다. 그 규모에서 순차 비교가 ANN보다 빠르고
--   무엇보다 **정확하다**(ANN은 근사라 임계값 바로 위의 후보를 놓칠 수 있는데, 이 기능에서
--   "놓침"은 AI를 한 번 더 부르는 손해로 끝나지만 **재현되지 않는 적중/미적중**은 디버깅을
--   불가능하게 만든다) (2) ivfflat은 학습 데이터가 있어야 제 성능이 나오고 지금은 데이터가 없다
--   (3) CLAUDE.md "미리 만들지 말 것". 행이 1만을 넘고 조회가 느려지면 그때 hnsw를 붙인다
--   (768차원이라 붙일 수 있다 - 그래서 3072차원을 고르지 않았다).
create index criteria_cache_lookup_idx
  on public.criteria_cache (type, ai_model, embedding_model, title_norm, created_at desc);

-- ---------------------------------------------------------------------------
-- 2) RLS - 정책을 **하나도** 만들지 않는다
-- ---------------------------------------------------------------------------
-- CLAUDE.md는 "RLS 정책은 테이블 만들 때 같이 작성한다"고 정한다. 이 테이블의 정답은 **정책 0개**다:
-- 어떤 사용자도 이 테이블을 직접 읽어서는 안 된다(spec 보안 성질 - "클라이언트가 캐시를 직접 읽어
-- 기준 텍스트를 들고 와 대결을 만드는 경로가 없다", "다른 사용자의 캐시 내용을 직접 조회하는
-- 클라이언트 경로가 없다"). RLS를 켜고 정책을 비우면 anon·authenticated는 0행을 본다.
-- Supabase는 public 스키마의 새 테이블에 anon·authenticated로 권한을 기본 부여하므로 권한까지 닫는다.
-- 닿는 길은 service_role(Edge Function)이 부르는 아래 함수들뿐이다.
alter table public.criteria_cache enable row level security;

revoke all on table public.criteria_cache from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) 아래 네 함수는 service_role 전용이다 - Edge Function battle-criteria가 부른다.
-- ---------------------------------------------------------------------------
-- CLAUDE.md의 "SECURITY DEFINER 함수는 auth.uid() is null 가드를 둔다" 규칙의 **예외**를 적용한다
-- (선례: settle_expired_battles, begin_criteria_call). service_role에는 auth.uid()가 없어 그 가드가
-- 항상 실패하기 때문이다. 대신 (1) authenticated까지 EXECUTE를 회수하고 (2) 사용자 id는 Edge Function이
-- JWT로 확인한 값을 인자로 넘기며 (3) 이 주석이 그 예외의 이유를 남긴다.

-- (3-1) 한도를 쓰지 않는 동의 관문.
--
-- **이 함수가 있어야 하는 이유**: 동의 확인은 지금 begin_criteria_call 안에 있고 그 함수는 확인과
-- **한도 예약을 한 트랜잭션에서 같이** 한다. 캐시 조회(임베딩 호출)는 동의 **뒤**에, 한도 예약
-- **앞**에 와야 하는데(design 3.1) 지금 그 사이에 설 자리가 없다. 그 자리를 이 함수가 만든다.
-- begin_criteria_call은 **한 줄도 바꾸지 않는다** - 동의 확인이 거기 남아 있어야 생성 경로의
-- 기존 보장("동의 전에는 Gemini를 부르지 않는다")이 이 함수의 존재와 무관하게 유지된다.
create function public.assert_criteria_consent(p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;
end;
$$;

comment on function public.assert_criteria_consent(uuid) is
  'AI 데이터 제공 동의만 확인한다(한도를 쓰지 않는다). 캐시 조회의 임베딩 호출 전에 부르는 관문 - '
  '동의 전에는 대결 제목이 임베딩으로도 Gemini에 가지 않는다. Edge Function 전용.';

-- (3-2) 캐시 조회. 정규화 일치 -> 벡터 유사도 순.
--
-- **반환값에 title_norm과 block_reason을 담지 않는다.** 원 제목과 원 차단 사유가 호출부로 나가지
-- 않으므로, 그것을 사용자에게 흘릴 코드가 Edge에 존재할 수 없다(design 원칙 8).
--
-- p_embedding을 text로 받는 이유: PostgREST가 JSON 배열을 vector로 바꿔 주는 동작에 의존하지
-- 않는다. Edge가 '[0.1,-0.2,...]' 문자열을 만들어 보내고(toVectorLiteral, 유닛 테스트 있음) 여기서
-- 한 번 캐스팅한다. 형식이 깨지면 예외가 나고, 호출부는 그것을 **미적중**으로 처리한다
-- (조회 실패가 기준 생성 실패가 되지 않는다 - 수용 기준 "기존 동작 보존").
--
-- p_min_similarity와 반환 similarity가 **double precision**인 이유: <=>가 double precision을
-- 돌려주는데 real로 받으면 0.95가 0.949999988...로 좁혀져 **SQL의 문턱이 코드 상수보다 약
-- 1.2e-8 낮아진다.** 임계값이 사는 자리는 코드 상수 하나라는 성질(design 원칙 7)을 숫자까지
-- 정확히 맞추려고 두 자리 모두 double precision으로 둔다. 그래야 SQL의 적중 판단과 Edge의
-- 재검증(parseCacheHit)이 같은 수를 같은 상수와 비교한다.
create function public.lookup_criteria_cache(
  p_type text,
  p_title_norm text,
  p_ai_model text,
  p_embedding_model text,
  p_embedding text default null,
  p_min_similarity double precision default null,
  p_include_blocked boolean default false
)
returns jsonb
language plpgsql
security definer set search_path = public, extensions
as $$
declare
  v_vec extensions.vector(768);
  v_hit jsonb;
begin
  if p_type not in ('speed', 'quality') then
    raise exception '올바르지 않은 대결 유형입니다.';
  end if;

  -- 경로 (1) 정규화 일치. 임베딩 없이도 되는 경로라 벡터 인자를 보지 않는다.
  -- "같은 주제에 여러 개면 가장 최근 것"(spec 탈출구 절)이 이 order by 한 줄이다.
  select jsonb_build_object(
           'cache_id', c.id,
           'type', c.type,
           'provable', c.provable,
           'min_criteria', c.min_criteria,
           'superiority_criteria', c.superiority_criteria,
           'ai_model', c.ai_model,
           'embedding_model', c.embedding_model,
           'similarity', 1.0,
           'matched_by', 'title'
         )
  into v_hit
  from public.criteria_cache c
  where c.type = p_type
    and c.ai_model = p_ai_model
    and c.embedding_model = p_embedding_model
    and c.title_norm = p_title_norm
    and (c.provable or p_include_blocked)
  order by c.created_at desc
  limit 1;

  if v_hit is not null then
    return v_hit;
  end if;

  -- 경로 (2) 벡터 유사도. 임베딩이 없으면(호출 실패했으면) 여기서 끝낸다 = 미적중.
  if p_embedding is null or p_min_similarity is null then
    return null;
  end if;

  v_vec := p_embedding::extensions.vector(768);

  select jsonb_build_object(
           'cache_id', c.id,
           'type', c.type,
           'provable', c.provable,
           'min_criteria', c.min_criteria,
           'superiority_criteria', c.superiority_criteria,
           'ai_model', c.ai_model,
           'embedding_model', c.embedding_model,
           'similarity', 1 - (c.embedding <=> v_vec),
           'matched_by', 'vector'
         )
  into v_hit
  from public.criteria_cache c
  where c.type = p_type
    and c.ai_model = p_ai_model
    and c.embedding_model = p_embedding_model
    and (c.provable or p_include_blocked)
    and (1 - (c.embedding <=> v_vec)) >= p_min_similarity
  order by c.embedding <=> v_vec asc, c.created_at desc
  limit 1;

  return v_hit;
end;
$$;

comment on function public.lookup_criteria_cache(text, text, text, text, text, double precision, boolean) is
  '재사용할 AI 원본 기준을 찾는다(정규화 일치 -> 벡터 유사도, 없으면 null). 원 제목·원 차단 사유· '
  '작성자는 반환하지 않는다. Edge Function 전용.';

-- (3-3) 적재. **AI 원본만** 들어온다.
--
-- 이 함수를 부르는 자리는 battle-criteria의 generate 성공 경로 **한 곳**이다. check(사용자 수정분
-- 재검사) 경로에는 호출이 없다 - 사용자가 쓴 문장이 캐시에 들어가는 길을 코드의 위치로 막는다
-- (spec 결정 4의 보안 성질). 같은 주제에 여러 행이 쌓이는 것은 정상이고, 조회가 가장 최근 것을
-- 고른다. 중복 제거·정리를 하지 않는다(지워야 할 행이 생기면 오너가 DB에서 직접 지운다 - spec 범위 밖).
create function public.put_criteria_cache(
  p_type text,
  p_title_norm text,
  p_provable boolean,
  p_min_criteria jsonb,
  p_superiority_criteria jsonb,
  p_block_reason text,
  p_ai_model text,
  p_embedding_model text,
  p_embedding text
)
returns uuid
language plpgsql
security definer set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  insert into public.criteria_cache (
    type, title_norm, provable, min_criteria, superiority_criteria,
    block_reason, ai_model, embedding_model, embedding
  )
  values (
    p_type,
    p_title_norm,
    p_provable,
    coalesce(p_min_criteria, '[]'::jsonb),
    p_superiority_criteria,
    p_block_reason,
    p_ai_model,
    p_embedding_model,
    p_embedding::extensions.vector(768)
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.put_criteria_cache(text, text, boolean, jsonb, jsonb, text, text, text, text) is
  'AI가 방금 만든 기준을 캐시에 넣는다. 사용자 수정분은 이 함수를 부르는 경로가 없다. '
  '적재 실패는 사용자의 기준 생성을 막지 않는다(호출부가 로그만 남긴다). Edge Function 전용.';

-- (3-4) 적중 -> 증서 1행. **원장(ai_criteria_calls)에 아무것도 쓰지 않는다.**
--
-- 대결 생성은 증서로만 되므로(create_battle) 적중도 증서를 만들어야 한다. 채우는 방식:
--   - title      : **호출자가 쓴 제목**을 그대로 넣는다. 캐시의 title_norm을 넣지 않는다
--                  (남의 제목이 내 대결 제목이 되는 일이 없어야 한다 - spec P0 조회 절).
--   - type·기준  : 캐시 행에서 그대로 복사한다(클라이언트가 보낸 텍스트를 쓰지 않는다).
--   - block_reason: 차단이면 **제목과 무관한 고정 문장**을 쓴다. 캐시의 원문은 원래 제목에 대한
--                  한 줄이라 다른 제목에 붙으면 틀린 설명이 된다(오너 결정 1이 남긴 숙제).
--   - ai_model   : 캐시의 값 + '/cache'. 어떤 코드도 이 컬럼을 읽지 않으므로(동작 변화 없음)
--                  오너가 "이 증서가 어디서 왔는가"를 DB에서 알아볼 수 있게 꼬리만 남긴다.
--                  이 값은 앱 응답에 들어가지 않는다(적중 여부가 화면으로 누설되지 않는다).
--                  머리 주석의 교차 검산식이 이 꼬리로 성립한다.
--   - consumed_at: null. created_at은 now()이므로 **증서의 24시간 만료는 발급 시점부터** 센다
--                  (캐시 행이 오래됐어도 증서는 신선하다). 1회 소진 규칙도 그대로다.
create function public.issue_cached_criteria_check(
  p_user_id uuid,
  p_title text,
  p_type text,
  p_cache_id uuid,
  p_ai_model text,
  p_embedding_model text
)
returns jsonb
language plpgsql
security definer set search_path = public, extensions
as $$
declare
  v_cache public.criteria_cache%rowtype;
  v_check_id uuid;
  v_block_reason text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  -- 조회와 증서 발급 사이에 동의를 철회했을 수도 있다. 증서는 동의 없이 생기지 않는다.
  perform public.assert_criteria_consent(p_user_id);

  -- 키를 다시 대조한다. 조회가 이미 걸렀지만, 증서를 만드는 자리에서 유형·버전을 한 번 더 본다
  -- (유형이 어긋난 기준으로 증서가 만들어지면 그 뒤의 모든 제약이 무의미해진다).
  select * into v_cache
  from public.criteria_cache
  where id = p_cache_id
    and type = p_type
    and ai_model = p_ai_model
    and embedding_model = p_embedding_model;

  if not found then
    raise exception using message = '사용할 수 없는 기준입니다.', hint = 'CHECK_INVALID';
  end if;

  if not v_cache.provable then
    -- 제목과 무관하게 참인 한 줄. 원래 제목의 사유를 복사하지 않는다.
    v_block_reason := '사진 한 장으로는 완료를 확인할 수 없는 주제로 보여요.';
  end if;

  insert into public.criteria_checks (
    user_id, action, battle_id, title, type,
    min_criteria, superiority_criteria, provable, block_reason, ai_model
  )
  values (
    p_user_id,
    'generate',
    null,
    btrim(p_title),
    v_cache.type,
    v_cache.min_criteria,
    v_cache.superiority_criteria,
    v_cache.provable,
    v_block_reason,
    v_cache.ai_model || '/cache'
  )
  returning id into v_check_id;

  -- calls_left는 finish_criteria_call과 **같은 식**이다. 적중은 원장을 건드리지 않았으므로 이 값이
  -- 요청 전과 같고, 화면의 `오늘 남은 기준 생성 N/10회`가 줄지 않는다(spec P0 한도 절).
  return jsonb_build_object(
    'check_id', v_check_id,
    'provable', v_cache.provable,
    'min_criteria', v_cache.min_criteria,
    'superiority_criteria', v_cache.superiority_criteria,
    'block_reason', v_block_reason,
    'calls_left', greatest(10 - public.criteria_calls_used(p_user_id, v_today), 0)
  );
end;
$$;

comment on function public.issue_cached_criteria_check(uuid, text, text, uuid, text, text) is
  '캐시 적중을 기준 증서 1행으로 만든다. 제목은 호출자가 쓴 것을 쓰고, 차단이면 제목과 무관한 '
  '고정 사유를 쓴다. 하루 10회 원장에는 아무것도 쓰지 않는다. Edge Function 전용.';

-- ---------------------------------------------------------------------------
-- 4) 권한. Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 준다.
--    네 함수 모두 사용자 롤이 직접 부를 수 있어서는 안 되므로 authenticated까지 회수한다.
-- ---------------------------------------------------------------------------
revoke execute on function public.assert_criteria_consent(uuid)
  from public, anon, authenticated;
revoke execute on function public.lookup_criteria_cache(text, text, text, text, text, double precision, boolean)
  from public, anon, authenticated;
revoke execute on function public.put_criteria_cache(text, text, boolean, jsonb, jsonb, text, text, text, text)
  from public, anon, authenticated;
revoke execute on function public.issue_cached_criteria_check(uuid, text, text, uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.assert_criteria_consent(uuid) to service_role;
grant execute on function public.lookup_criteria_cache(text, text, text, text, text, double precision, boolean)
  to service_role;
grant execute on function public.put_criteria_cache(text, text, boolean, jsonb, jsonb, text, text, text, text)
  to service_role;
grant execute on function public.issue_cached_criteria_check(uuid, text, text, uuid, text, text)
  to service_role;
