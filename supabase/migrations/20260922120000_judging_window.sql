-- mutual-judge 2단계: 판정 창·제출 교체·상호 판정 기록(즉시 AI 판정 제거).
--
-- 근거: docs/specs/mutual-judge/spec.md "P0. 상호 판정의 절차", "P0. 제출 교체",
-- docs/specs/mutual-judge/design.md "상태 전이", "데이터 모델", "제출 교체와 경합",
-- "API 계약", "주기 작업(cron) 구성".
--
-- 핵심 규칙
--   - judging의 뜻이 바뀐다: "AI 판정 대기"가 아니라 "참가자 상호 판정 대기"다. 속도전도 이제
--     judging을 거친다. AI 재판정은 그 안의 갈래이고, 배선은 3단계가 한다.
--   - 판정 창은 (a) 양쪽 제출 또는 (b) 마감 중 먼저 오는 것으로 열린다. 열리는 순간 양쪽 증거가
--     동시에 공개된다. 마감 전에는 "제출했다"는 사실 하나만 상대에게 보인다.
--   - 속도전은 상대가 아직 제출하지 않은 동안 사진을 몇 번이든 교체할 수 있다(제출 시각 갱신).
--     상대가 제출하면 잠긴다. 품질전은 교체가 없다(제출 1회).
--   - 판정 기한은 "판정 창이 열린 시각 + 24시간" 고정이다. 미판정은 승인으로 간주한다.
--   - 이 단계는 AI 재판정 배선(ai_judgment_jobs 등, 3단계)을 만들지 않는다. 그래서 불복(reject)이
--     걸린 제출은 AI 결과가 없는 한 'pending'에 머물고 대결은 judging에서 더 나가지 못한다 —
--     지금은 판정 화면이 없으므로(4단계) 실사용자가 이 상태에 이를 길이 없고, SQL 테스트에서만
--     직접 submit_judgment를 불러 이 상태를 본다. 3단계가 resolve_battle을 다시 고쳐
--     ensure_ai_judgment_job을 그 자리에 끼워 넣는다.
--   - 배포된 submit-evidence Edge Function이 accept_submission을 부르므로 그 시그니처
--     (uuid, uuid, text, timestamptz)는 유지한다. **원격 적용 직후 submit-evidence를 재배포해야
--     한다** — 이 마이그레이션이 지우는 record_speed_verdict를 옛 함수가 그대로 부르기 때문이다.

-- ---------------------------------------------------------------------------
-- battles: 판정 창 두 컬럼
-- ---------------------------------------------------------------------------
alter table public.battles
  add column judging_opened_at timestamptz,
  add column judge_deadline_at timestamptz;

alter table public.battles
  add constraint battles_judging_window_pair_check
    check ((judging_opened_at is null) = (judge_deadline_at is null)),
  add constraint battles_judging_requires_window_check
    check (status <> 'judging' or judging_opened_at is not null);

comment on column public.battles.judging_opened_at is
  '판정 창이 열린 서버 시각. null이면 아직 제출 창(active)이다. open_judging_window만 이 값을 채운다.';
comment on column public.battles.judge_deadline_at is
  '판정 기한(판정 창이 열린 시각 + 24시간). 지나면 close_expired_judging_windows가 미판정을 자동 승인으로 채운다.';

comment on column public.battles.status is
  'pending(모집 중) -> active(매칭됨, 제출 창) -> judging(상호 판정 창, 두 유형 공통) -> '
  'finished(승자 있음) | draw | voided(불복·불일치 AI 재판정이 끝내 실패) | cancelled. '
  'disputed는 유료 재심용 개념으로만 남고 MVP의 어떤 함수도 이 값을 쓰지 않는다.';

-- 1분 주기 cron이 두 테이블(active/judging)을 전체 스캔하지 않게 조건부 인덱스를 둔다.
create index battles_judge_deadline_at_idx
  on public.battles (judge_deadline_at) where status = 'judging';
create index battles_deadline_at_idx
  on public.battles (deadline_at) where status = 'active';

-- ---------------------------------------------------------------------------
-- battle_participants: 요약 컬럼 교체 (상대도 전부 읽는다는 불변식을 못박는다)
-- ---------------------------------------------------------------------------
-- first_submitted_at(상대의 제출 시각)·last_verdict(상대의 합격/불합격)·passed_at(상대의 통과
-- 시각)은 전부 spec이 "마감 전에 숨기라"고 한 값이다. 이 테이블은 참가자 둘 다 읽으므로
-- (아래 정책 주석 참고) 시각·판정 내용을 담으면 그 자리에서 상대에게 샌다. 불린 두 개로 교체해
-- "제출했다"·"판정했다"는 사실만 남긴다.
alter table public.battle_participants
  drop column first_submitted_at,
  drop column attempts_used,
  drop column last_verdict,
  drop column passed_at;

alter table public.battle_participants
  add column has_submitted boolean not null default false,
  add column has_judged boolean not null default false;

comment on column public.battle_participants.has_submitted is
  '이 사람이 증거를 제출했는지. 시각·사진·통과 여부는 담지 않으므로 상대에게 보여도 된다.';
comment on column public.battle_participants.has_judged is
  '이 사람이 판정(자동 승인 포함)을 마쳤는지. 무엇으로 판정했는지는 담지 않는다.';

comment on table public.battle_participants is
  '대결 참가자별 진행 요약. ** 이 테이블의 모든 컬럼은 상대 참가자도 읽는다 ** — select 정책 '
  '"participants can view their battle progress"가 행 단위(대결의 참가자인지)만 보고 user_id로 '
  '좁히지 않기 때문이다. 그래서 진행 중 상대에게 공개해도 되는 요약만 둔다. 새 컬럼을 더하면 '
  '자동으로 상대에게 공개된다 — 시점에 따라 가려야 하는 값(시각·사진·판정 내용)은 '
  'battle_submissions·battle_judgments·Storage에 두고, 그 테이블들이 judging_opened_at으로 '
  '시점을 가른다.';

comment on policy "participants can view their battle progress" on public.battle_participants is
  '행 단위 정책이라 user_id로 좁히지 않는다 — 참가자는 상대 행도 전부 읽는다. 위 테이블 주석의 '
  '불변식이 바로 이 정책 때문에 성립한다.';

-- ---------------------------------------------------------------------------
-- battle_submissions: 참가자당 한 행(교체는 덮어쓰기)
-- ---------------------------------------------------------------------------
-- status(judging/passed/failed/error/submitted)는 제출 즉시 AI 판정이 있던 시절의 개념이다.
-- 이제 제출은 '제출됨' 하나뿐이고 결론은 meets_criteria·verdict_source가 따로 담는다.
drop index if exists public.battle_submissions_one_judging_idx;
drop index if exists public.battle_submissions_one_passed_idx;
drop index if exists public.battle_submissions_one_quality_idx;
drop index if exists public.battle_submissions_battle_user_idx;

alter table public.battle_submissions
  drop column status,
  drop column judging_started_at;

alter table public.battle_submissions
  add constraint battle_submissions_battle_user_unique unique (battle_id, user_id),
  add column verdict_source text
    constraint battle_submissions_verdict_source_check
      check (verdict_source in ('opponent', 'auto', 'ai'));

comment on table public.battle_submissions is
  '증거 사진 제출 원장. 참가자당 한 행이고 교체는 이 행의 덮어쓰기다(속도전만, 상대가 아직 '
  '제출하지 않은 동안). 진행 중에는 본인 행만 보이고, 판정 창이 열리거나(judging_opened_at이 '
  '찍히거나) 대결이 종결된 뒤에 상대 행이 열린다.';
comment on column public.battle_submissions.submitted_at is
  '서버 수신 시각. 속도전 승부 기준. 교체하면 갱신된다(빨리 눌러 선점하고 나중에 바꾸는 전략을 막는다).';
comment on column public.battle_submissions.meets_criteria is
  '최소 기준 결론. 승인/자동 승인/AI 재판정으로 정해지며, 미결이면 null이다.';
comment on column public.battle_submissions.verdict_source is
  '최소 기준 결론을 누가 정했는지: opponent(상대가 승인) / auto(판정 기한 경과로 자동 승인) / '
  'ai(불복 후 AI 재판정). null이면 아직 결론이 없다.';
comment on column public.battle_submissions.reason is
  'AI 재판정의 한 줄 사유. 사람 판정(승인/자동 승인)에는 사유가 없다.';

-- select 정책 교체: 마감 전·판정 창 전에는 상대 행이 보이지 않는다. 판정 창이 열리면(=양쪽 제출
-- 또는 마감) 종결을 기다리지 않고 바로 열린다.
drop policy "users can view own submissions or finished battle submissions" on public.battle_submissions;

create policy "users can view own submissions or judging or finished battle submissions"
  on public.battle_submissions for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.battles b
      where b.id = battle_id
        and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
        and (
          b.judging_opened_at is not null
          or b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed')
        )
    )
  );

-- ---------------------------------------------------------------------------
-- battle_judgments: 참가자 상호 판정 기록 (신규)
-- ---------------------------------------------------------------------------
-- 판정 대상 컬럼을 두지 않는다. 2인 대결이므로 대상은 항상 judge_id의 상대다
-- (CLAUDE.md "3인 이상 구조를 미리 만들지 말 것").
create table public.battle_judgments (
  battle_id uuid not null references public.battles (id) on delete cascade,
  judge_id uuid not null references public.profiles (id) on delete cascade,
  min_verdict text not null check (min_verdict in ('approve', 'reject')),
  superior_id uuid references public.profiles (id),
  auto boolean not null default false,
  decided_at timestamptz not null default now(),
  primary key (battle_id, judge_id)
);

comment on table public.battle_judgments is
  '참가자 상호 판정 기록. 판정 대상 컬럼은 없다(대상은 항상 judge_id의 상대). superior_id는 '
  '품질전에서 더 잘했다고 고른 사람의 절대 user id(속도전은 항상 null). auto=true면 판정 기한 '
  '경과로 서버가 채운 행. 한 사람의 판정은 PK로 강제되는 한 번뿐이다(수정·철회 수단 없음).';

alter table public.battle_judgments enable row level security;

-- 판정 창 중에 상대의 판정 내용이 보이면 상대 답을 보고 내 답을 고르는 경로가 생긴다.
-- 그래서 내 행은 언제나, 상대 행은 대결이 종결된 뒤에만 보인다.
create policy "judges can view their own judgment or finished battle judgments"
  on public.battle_judgments for select
  to authenticated
  using (
    judge_id = auth.uid()
    or exists (
      select 1 from public.battles b
      where b.id = battle_id
        and b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed')
        and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
    )
  );

-- insert/update/delete 정책은 두지 않는다. 쓰기는 submit_judgment·close_expired_judging_windows만.

-- ---------------------------------------------------------------------------
-- Storage(battle_evidence): 판정 창 기준으로 insert/select 정책 교체
-- ---------------------------------------------------------------------------
drop policy "participants can upload evidence to own folder" on storage.objects;
drop policy "users can read own evidence or finished battle evidence" on storage.objects;

-- 교체 업로드가 판정 창이 열린 뒤에 끼어들지 못하게 status='active'와 judging_opened_at is null을
-- 함께 본다(status 검사가 이미 함의하지만 두 번 본다).
create policy "participants can upload evidence to own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.battles b
      where b.id::text = (storage.foldername(name))[1]
        and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
        and b.status = 'active'
        and b.deadline_at > now()
        and b.judging_opened_at is null
    )
  );

-- 조회: 내 사진은 언제든, 상대 사진은 판정 창이 열리거나(마감 전이라도) 종결된 뒤에만.
-- createSignedUrl도 이 정책을 거치므로 마감 전 상대 사진은 서명 URL 발급 자체가 실패한다.
create policy "users can read own evidence or judging or finished battle evidence"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or exists (
        select 1 from public.battles b
        where b.id::text = (storage.foldername(name))[1]
          and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
          and (
            b.judging_opened_at is not null
            or b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed')
          )
      )
    )
  );

-- delete 정책(본인 폴더)은 그대로 둔다(변경 없음).

-- ---------------------------------------------------------------------------
-- 판정 규칙 순수 함수 4개 (신규) — 옛 3개(speed_outcome·quality_outcome·quality_deadline_outcome) 대체
-- ---------------------------------------------------------------------------
-- 전부 데이터를 읽지 않는 순수 함수다. 앱이 부를 이유가 없으므로 EXECUTE를 전부 회수한다
-- (SECURITY DEFINER가 아니므로 로그인 가드 규칙 대상도 아니다).

-- 판정 창을 여는 규칙. a/b는 호출부가 역할(속도전 제출자 둘, 또는 creator/opponent)에 맞게
-- 넘긴다 — 이 함수는 누가 a이고 b인지 모른다.
create function public.judging_gate(
  p_type text,
  p_a_submitted boolean,
  p_b_submitted boolean,
  p_deadline_passed boolean,
  out action text
)
language plpgsql
immutable
set search_path = public
as $$
begin
  -- 양쪽 제출 -> 마감을 기다리지 않고 그 즉시 연다(두 유형 공통).
  if coalesce(p_a_submitted, false) and coalesce(p_b_submitted, false) then
    action := 'open';
    return;
  end if;

  if not coalesce(p_deadline_passed, false) then
    action := 'wait';
    return;
  end if;

  if p_type = 'speed' then
    -- 속도전 한쪽만 제출 -> 그 제출을 판정할 사람(제출하지 않은 쪽)이 있으므로 창을 연다.
    if coalesce(p_a_submitted, false) or coalesce(p_b_submitted, false) then
      action := 'open';
    else
      action := 'draw';
    end if;
    return;
  end if;

  -- 품질전 한쪽만 제출 -> 판정할 상대 증거가 없다. 창 없이 제출한 쪽이 바로 이긴다.
  if coalesce(p_a_submitted, false) then
    action := 'finish_a';
  elsif coalesce(p_b_submitted, false) then
    action := 'finish_b';
  else
    action := 'draw';
  end if;
end;
$$;

comment on function public.judging_gate is
  '판정 창을 열지(open), 기다릴지(wait), 창 없이 바로 끝낼지(finish_a/finish_b/draw)를 정하는 '
  '순수 함수. a/b는 역할 중립이다(creator/opponent로 고정되지 않는다). 내부 전용.';

-- 제출 하나의 최소 기준 결론. p_opponent_verdict는 "이 제출을 판정하는 사람"(=상대)의 min_verdict다.
create function public.min_verdict_effect(
  p_submitted boolean,
  p_opponent_verdict text,
  p_ai_meets boolean
)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if not coalesce(p_submitted, false) then
    return 'none';
  end if;

  if p_opponent_verdict is null then
    return 'pending';
  end if;

  if p_opponent_verdict = 'approve' then
    return 'pass';
  end if;

  -- reject: AI 재판정이 사람의 판정을 대체한다(거짓 불복이 이득이 되지 않는 지점).
  if p_ai_meets is null then
    return 'pending';
  end if;

  return case when p_ai_meets then 'pass' else 'fail' end;
end;
$$;

comment on function public.min_verdict_effect is
  '제출 하나의 최소 기준 결론(none/pending/pass/fail). reject는 AI 결과가 올 때까지 pending이고, '
  'AI가 통과라고 하면 사람의 불복을 뒤집는다. 내부 전용.';

-- 속도전 결과. 호출 전에 pending이 없어야 한다(있으면 resolve_battle이 기다린다).
create function public.mutual_speed_outcome(
  p_a_effect text,
  p_a_submitted_at timestamptz,
  p_a_seq bigint,
  p_b_effect text,
  p_b_submitted_at timestamptz,
  p_b_seq bigint,
  out status text,
  out winner text,
  out a_outcome text,
  out b_outcome text
)
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_a_effect = 'pass' and p_b_effect = 'pass' then
    status := 'finished';
    -- 이른 제출 시각이 승리. 동률이면 먼저 기록된 행(seq가 작은 쪽)이 이긴다.
    if p_a_submitted_at < p_b_submitted_at
       or (p_a_submitted_at = p_b_submitted_at and p_a_seq < p_b_seq) then
      winner := 'a'; a_outcome := 'win'; b_outcome := 'completed_loss';
    else
      winner := 'b'; a_outcome := 'completed_loss'; b_outcome := 'win';
    end if;
    return;
  end if;

  if p_a_effect = 'pass' then
    status := 'finished'; winner := 'a'; a_outcome := 'win'; b_outcome := 'loss';
    return;
  end if;

  if p_b_effect = 'pass' then
    status := 'finished'; winner := 'b'; a_outcome := 'loss'; b_outcome := 'win';
    return;
  end if;

  status := 'draw'; a_outcome := 'draw'; b_outcome := 'draw';
end;
$$;

comment on function public.mutual_speed_outcome is
  '속도전 결과(순수 함수). 유효한 완료(pass)로 확정된 제출 중 서버 시각이 이른 쪽이 승리. '
  '호출 전 pending이 없어야 한다. 내부 전용.';

-- 품질전 결과. next='ai'면 아직 끝나지 않았다(우열 AI 재판정이 필요하다 — 3단계가 그 잡을 만든다).
create function public.mutual_quality_outcome(
  p_a_effect text,
  p_b_effect text,
  p_a_pick text,
  p_b_pick text,
  out next text,
  out status text,
  out winner text,
  out a_outcome text,
  out b_outcome text
)
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_a_effect = 'pass' and p_b_effect = 'fail' then
    next := 'finish'; status := 'finished';
    winner := 'a'; a_outcome := 'win'; b_outcome := 'loss';
    return;
  end if;

  if p_a_effect = 'fail' and p_b_effect = 'pass' then
    next := 'finish'; status := 'finished';
    winner := 'b'; a_outcome := 'loss'; b_outcome := 'win';
    return;
  end if;

  if p_a_effect = 'fail' and p_b_effect = 'fail' then
    next := 'draw'; status := 'draw'; a_outcome := 'draw'; b_outcome := 'draw';
    return;
  end if;

  -- 둘 다 pass -> 우열로 간다.
  if p_a_pick is null and p_b_pick is null then
    -- 아무도 판정하지 않았다. 가를 근거가 없다(무임승차 방지 — AI를 부르지 않는다).
    next := 'draw'; status := 'draw'; a_outcome := 'draw'; b_outcome := 'draw';
    return;
  end if;

  if p_a_pick is not null and p_b_pick is null then
    -- 한쪽만 답함 -> 답한 쪽 답대로 확정(미답은 승복으로 간주).
    next := 'finish'; status := 'finished';
    winner := p_a_pick;
    a_outcome := case when p_a_pick = 'a' then 'win' else 'loss' end;
    b_outcome := case when p_a_pick = 'b' then 'win' else 'loss' end;
    return;
  end if;

  if p_b_pick is not null and p_a_pick is null then
    next := 'finish'; status := 'finished';
    winner := p_b_pick;
    a_outcome := case when p_b_pick = 'a' then 'win' else 'loss' end;
    b_outcome := case when p_b_pick = 'b' then 'win' else 'loss' end;
    return;
  end if;

  if p_a_pick = p_b_pick then
    -- 같은 사람을 가리킴 -> 합의. AI 호출 없음.
    next := 'finish'; status := 'finished';
    winner := p_a_pick;
    a_outcome := case when p_a_pick = 'a' then 'win' else 'loss' end;
    b_outcome := case when p_a_pick = 'b' then 'win' else 'loss' end;
    return;
  end if;

  -- 서로 어긋남(둘 다 자기 승리 주장, 또는 둘 다 상대 승리 주장) -> 아무도 승복하지 않았다.
  -- AI가 우열 기준으로 가른다(3단계가 그 잡을 만든다).
  next := 'ai'; status := 'judging';
end;
$$;

comment on function public.mutual_quality_outcome is
  '품질전 결과(순수 함수). next=finish|draw면 이미 끝난 결론이고, next=ai면 우열 AI 재판정이 '
  '필요하다(3단계가 잡을 만든다). 호출 전 pending이 없어야 한다. 내부 전용.';

drop function public.speed_outcome(
  timestamptz, bigint, integer, boolean, timestamptz, bigint, integer, boolean, boolean
);
drop function public.quality_outcome(boolean, boolean, text);
drop function public.quality_deadline_outcome(boolean, boolean);

revoke execute on function public.judging_gate(text, boolean, boolean, boolean)
  from public, anon, authenticated;
revoke execute on function public.min_verdict_effect(boolean, text, boolean)
  from public, anon, authenticated;
revoke execute on function public.mutual_speed_outcome(
  text, timestamptz, bigint, text, timestamptz, bigint
) from public, anon, authenticated;
revoke execute on function public.mutual_quality_outcome(text, text, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- open_judging_window: 판정 창을 여는 유일한 지점 (내부 전용, 신규)
-- ---------------------------------------------------------------------------
-- accept_submission(양쪽 제출)과 settle_expired_battles(마감)만 부른다. 호출자가 이미
-- battles 행을 for update로 잠그고 있다는 전제다. 기산점을 한 곳에 모아 "now() + interval
-- '24 hours'" 표현식이 코드에 한 번만 있게 한다.
create function public.open_judging_window(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.battles
  set status = 'judging',
      judging_opened_at = now(),
      judge_deadline_at = now() + interval '24 hours'
  where id = p_battle_id;
end;
$$;

comment on function public.open_judging_window is
  '판정 창을 연다(서버 시각 + 24시간 고정). accept_submission·settle_expired_battles만 부른다. '
  '내부 전용.';

revoke execute on function public.open_judging_window(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- resolve_battle 재작성: 상호 판정 결론으로 종결 여부를 본다
-- ---------------------------------------------------------------------------
-- 시그니처(uuid -> text)는 유지한다. 2단계에는 AI 재판정 잡 인프라가 없으므로, pending(불복한
-- 제출에 AI 결과가 아직 없음, 또는 품질전 우열 불일치)이 있으면 그대로 'judging'을 반환하고
-- 기다린다 — 3단계가 이 함수를 다시 고쳐 그 자리에 ensure_ai_judgment_job을 끼워 넣는다.
create or replace function public.resolve_battle(p_battle_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_a_sub public.battle_submissions%rowtype;
  v_b_sub public.battle_submissions%rowtype;
  v_creator_judgment public.battle_judgments%rowtype;
  v_opponent_judgment public.battle_judgments%rowtype;
  v_a_effect text;
  v_b_effect text;
  v_a_pick text;
  v_b_pick text;
  v_speed record;
  v_quality record;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  -- status='active'로 불렸을 때는 판정이 있을 수 없다(창이 아직 안 열렸다). cron이
  -- judging_gate로 따로 본다. 종결된 대결도 그대로 반환한다(늦게 온 판정이 다시 건드리지 않게).
  if v_battle.status <> 'judging' or v_battle.opponent_id is null then
    return v_battle.status;
  end if;

  select * into v_a_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.creator_id;
  select * into v_b_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.opponent_id;
  -- creator_judgment = creator_id가 낸 판정(= 상대 제출에 대한 판정 + 자기 우열 선택).
  select * into v_creator_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.creator_id;
  select * into v_opponent_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.opponent_id;

  -- a(creator) 제출의 결론은 상대(opponent)의 판정을 본다. b는 반대.
  v_a_effect := public.min_verdict_effect(
    v_a_sub.id is not null, v_opponent_judgment.min_verdict, v_a_sub.meets_criteria
  );
  v_b_effect := public.min_verdict_effect(
    v_b_sub.id is not null, v_creator_judgment.min_verdict, v_b_sub.meets_criteria
  );

  if v_a_effect = 'pending' or v_b_effect = 'pending' then
    return 'judging';
  end if;

  if v_battle.type = 'speed' then
    select * into v_speed from public.mutual_speed_outcome(
      v_a_effect, v_a_sub.submitted_at, v_a_sub.id,
      v_b_effect, v_b_sub.submitted_at, v_b_sub.id
    );

    perform public.finalize_battle(
      p_battle_id,
      v_speed.status,
      case v_speed.winner
        when 'a' then v_battle.creator_id
        when 'b' then v_battle.opponent_id
        else null
      end,
      v_speed.a_outcome,
      v_speed.b_outcome
    );

    return v_speed.status;
  end if;

  -- 품질전 우열 선택. a_pick = creator가 고른 승자, b_pick = opponent가 고른 승자(둘 다 'a'/'b' 슬롯).
  v_a_pick := case
    when v_creator_judgment.superior_id is null then null
    when v_creator_judgment.superior_id = v_battle.creator_id then 'a'
    when v_creator_judgment.superior_id = v_battle.opponent_id then 'b'
    else null
  end;
  v_b_pick := case
    when v_opponent_judgment.superior_id is null then null
    when v_opponent_judgment.superior_id = v_battle.creator_id then 'a'
    when v_opponent_judgment.superior_id = v_battle.opponent_id then 'b'
    else null
  end;

  select * into v_quality
  from public.mutual_quality_outcome(v_a_effect, v_b_effect, v_a_pick, v_b_pick);

  if v_quality.next = 'ai' then
    -- 3단계가 여기에 ensure_ai_judgment_job(battle, 'superiority', null)을 끼워 넣는다.
    return 'judging';
  end if;

  perform public.finalize_battle(
    p_battle_id,
    v_quality.status,
    case v_quality.winner
      when 'a' then v_battle.creator_id
      when 'b' then v_battle.opponent_id
      else null
    end,
    v_quality.a_outcome,
    v_quality.b_outcome
  );

  return v_quality.status;
end;
$$;

comment on function public.resolve_battle is
  '상호 판정 결론으로 종결 여부를 계산해 finalize_battle로 적용한다. pending(불복 AI 대기, 우열 '
  '불일치)이 있으면 judging을 반환하고 기다린다(3단계가 AI 잡을 배선한다). 내부 전용.';

-- ---------------------------------------------------------------------------
-- settle_expired_battles 재작성: active만 본다, judging_gate로 정산
-- ---------------------------------------------------------------------------
-- 이제 judging은 "상호 판정 창"이므로 마감(제출 창의 끝)이 지나도 손대지 않는다 —
-- 판정 창은 judge_deadline_at이 지배하고 close_expired_judging_windows가 본다.
-- 한 대결의 예외가 같은 tick의 다른 대결을 막지 않게 반복마다 예외를 흡수한다(design "주기 작업").
create or replace function public.settle_expired_battles()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_creator_submitted boolean;
  v_opponent_submitted boolean;
  v_gate text;
  v_settled integer := 0;
begin
  for v_battle in
    select * from public.battles
    where status = 'active'
      and deadline_at is not null
      and deadline_at <= now()
      and opponent_id is not null
    order by deadline_at
    for update skip locked
  loop
    begin
      select exists (
        select 1 from public.battle_submissions
        where battle_id = v_battle.id and user_id = v_battle.creator_id
      ) into v_creator_submitted;
      select exists (
        select 1 from public.battle_submissions
        where battle_id = v_battle.id and user_id = v_battle.opponent_id
      ) into v_opponent_submitted;

      v_gate := public.judging_gate(v_battle.type, v_creator_submitted, v_opponent_submitted, true);

      if v_gate = 'open' then
        perform public.open_judging_window(v_battle.id);
        v_settled := v_settled + 1;
      elsif v_gate = 'finish_a' then
        perform public.finalize_battle(v_battle.id, 'finished', v_battle.creator_id, 'win', 'loss');
        v_settled := v_settled + 1;
      elsif v_gate = 'finish_b' then
        perform public.finalize_battle(v_battle.id, 'finished', v_battle.opponent_id, 'loss', 'win');
        v_settled := v_settled + 1;
      elsif v_gate = 'draw' then
        perform public.finalize_battle(v_battle.id, 'draw', null, 'draw', 'draw');
        v_settled := v_settled + 1;
      end if;
      -- v_gate='wait'는 deadline_passed=true로 불렀으므로 나오지 않는다(방어적으로 아무것도 안 함).
    exception when others then
      raise warning '마감 정산 실패 (battle=%): %', v_battle.id, sqlerrm;
    end;
  end loop;

  return v_settled;
end;
$$;

comment on function public.settle_expired_battles is
  '제출 창 마감이 지난 active 대결을 judging_gate로 정산한다(열기/즉시 종결/무승부). judging은 '
  'close_expired_judging_windows가 따로 본다. cron 전용.';

revoke execute on function public.settle_expired_battles() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- close_expired_judging_windows: 판정 기한이 지난 미판정을 자동 승인으로 채운다 (신규, cron)
-- ---------------------------------------------------------------------------
-- 필요한 판정(= 상대가 제출한 쪽의 판정)만 "insert ... on conflict do nothing"으로 채운다.
-- 이미 판정(승인이든 불복이든)한 사람의 행은 건드리지 않는다 — 미판정만 승인으로 간주한다.
-- cron·service 롤에는 auth.uid()가 없어 로그인 가드를 두지 않는다(settle_expired_battles와
-- 같은 예외). EXECUTE는 전부 회수한다.
create function public.close_expired_judging_windows()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle_id uuid;
  v_creator_id uuid;
  v_opponent_id uuid;
  v_creator_submitted boolean;
  v_opponent_submitted boolean;
  v_closed integer := 0;
begin
  for v_battle_id, v_creator_id, v_opponent_id in
    select b.id, b.creator_id, b.opponent_id
    from public.battles b
    where b.status = 'judging'
      and b.judge_deadline_at is not null
      and b.judge_deadline_at <= now()
    order by b.judge_deadline_at
    for update skip locked
  loop
    begin
      select exists (
        select 1 from public.battle_submissions
        where battle_id = v_battle_id and user_id = v_creator_id
      ) into v_creator_submitted;
      select exists (
        select 1 from public.battle_submissions
        where battle_id = v_battle_id and user_id = v_opponent_id
      ) into v_opponent_submitted;

      -- opponent가 제출했으면 creator가 그것을 판정해야 한다. 안 했으면 자동 승인으로 채운다.
      if v_opponent_submitted then
        insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
        values (v_battle_id, v_creator_id, 'approve', null, true)
        on conflict (battle_id, judge_id) do nothing;

        if found then
          update public.battle_participants
          set has_judged = true
          where battle_id = v_battle_id and user_id = v_creator_id;

          update public.battle_submissions
          set meets_criteria = true, verdict_source = 'auto'
          where battle_id = v_battle_id and user_id = v_opponent_id;
        end if;
      end if;

      if v_creator_submitted then
        insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
        values (v_battle_id, v_opponent_id, 'approve', null, true)
        on conflict (battle_id, judge_id) do nothing;

        if found then
          update public.battle_participants
          set has_judged = true
          where battle_id = v_battle_id and user_id = v_opponent_id;

          update public.battle_submissions
          set meets_criteria = true, verdict_source = 'auto'
          where battle_id = v_battle_id and user_id = v_creator_id;
        end if;
      end if;

      -- 양쪽 판정과 필요한 AI 재판정이 모두 끝났으면 즉시 종결한다. 아직 AI 잡이 남아 있으면
      -- (3단계부터) judging으로 그대로 둔다 — 판정 기한이 진행 중인 재판정을 죽이지 않는다.
      perform public.resolve_battle(v_battle_id);
      v_closed := v_closed + 1;
    exception when others then
      raise warning '판정 기한 자동 승인 실패 (battle=%): %', v_battle_id, sqlerrm;
    end;
  end loop;

  return v_closed;
end;
$$;

comment on function public.close_expired_judging_windows is
  '판정 기한이 지난 judging 대결의 미판정(상대가 제출한 쪽만)을 자동 승인으로 채우고 종결 여부를 '
  '다시 본다. 이미 낸 판정(승인·불복)은 건드리지 않는다. cron 전용.';

revoke execute on function public.close_expired_judging_windows() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- submit_judgment: 참가자 상호 판정 (신규, 앱이 부르는 RPC)
-- ---------------------------------------------------------------------------
create function public.submit_judgment(
  p_battle_id uuid,
  p_min_verdict text,
  p_superior_id uuid
)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_opponent_id uuid;
  v_opponent_submitted boolean;
  v_status text;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_min_verdict not in ('approve', 'reject') then
    raise exception '판정 값이 올바르지 않습니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if auth.uid() is distinct from v_battle.creator_id
     and auth.uid() is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if v_battle.status <> 'judging' then
    raise exception using message = '아직 판정할 수 있는 상태가 아닙니다.', hint = 'JUDGING_NOT_OPEN';
  end if;

  if v_battle.judge_deadline_at is null or v_battle.judge_deadline_at <= now() then
    raise exception using message = '판정 기한이 지나 자동으로 처리됐습니다.', hint = 'JUDGE_WINDOW_CLOSED';
  end if;

  v_opponent_id := case
    when auth.uid() = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  select exists (
    select 1 from public.battle_submissions where battle_id = p_battle_id and user_id = v_opponent_id
  ) into v_opponent_submitted;

  if not v_opponent_submitted then
    raise exception using message = '판정할 증거가 없습니다.', hint = 'NOTHING_TO_JUDGE';
  end if;

  if v_battle.type = 'speed' then
    if p_superior_id is not null then
      raise exception '속도전은 우열을 매기지 않습니다.';
    end if;
  else
    -- 두 질문을 한 번에 받는다(왕복을 늘리지 않는다). 품질전은 항상 우열 답이 필요하다.
    if p_superior_id is null then
      raise exception using message = '누가 더 잘했는지 골라 주세요.', hint = 'SUPERIORITY_REQUIRED';
    end if;
    if p_superior_id is distinct from v_battle.creator_id
       and p_superior_id is distinct from v_battle.opponent_id then
      raise exception '우열 선택이 이 대결의 참가자가 아닙니다.';
    end if;
  end if;

  begin
    insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
    values (p_battle_id, auth.uid(), p_min_verdict, p_superior_id, false);
  exception when unique_violation then
    raise exception using message = '이미 판정했습니다.', hint = 'ALREADY_JUDGED';
  end;

  update public.battle_participants
  set has_judged = true
  where battle_id = p_battle_id and user_id = auth.uid();

  -- 승인 경로는 결론 계산에 쓰이지 않지만(min_verdict_effect가 approve를 그대로 통과시킨다)
  -- 종결 뒤 화면이 "누가 인정했는지"를 보여주려면 필요하다(verdict_source).
  if p_min_verdict = 'approve' then
    update public.battle_submissions
    set meets_criteria = true, verdict_source = 'opponent'
    where battle_id = p_battle_id and user_id = v_opponent_id;
  end if;

  v_status := public.resolve_battle(p_battle_id);

  return v_status;
end;
$$;

comment on function public.submit_judgment is
  '참가자 상호 판정. 승인/불복과(품질전이면) 우열을 한 번에 받는다. 한 사람당 한 번뿐이다.';

revoke execute on function public.submit_judgment(uuid, text, uuid) from public, anon;
grant execute on function public.submit_judgment(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- accept_submission 재정의: 제출·교체, 양쪽 제출 시 판정 창 열기 (시그니처 유지)
-- ---------------------------------------------------------------------------
-- status='active'인 동안에는 참가자당 제출 행이 최대 하나만 존재한다(둘 다 내면 이 함수 안에서
-- 같은 트랜잭션으로 판정 창이 열려 status가 바뀌기 때문이다). 그래서 "내 행이 있는가"만으로
-- 교체(속도전)와 첫 제출을 가를 수 있고, 상대 행이 있을 수 있는 유일한 경우는 "내가 지금 두 번째로
-- 내는 참가자"일 때뿐이다.
create or replace function public.accept_submission(
  p_user_id uuid,
  p_battle_id uuid,
  p_object_path text,
  p_captured_at timestamptz
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_now timestamptz := now();
  v_opponent_id uuid;
  v_my_submission public.battle_submissions%rowtype;
  v_opponent_submitted boolean;
  v_submission public.battle_submissions%rowtype;
  v_replaced_path text;
  v_gate text;
  v_judging_opened boolean := false;
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  if p_object_path is null or length(btrim(p_object_path)) = 0 then
    raise exception '사진 경로가 필요합니다.';
  end if;

  if p_captured_at is null then
    raise exception '촬영 시각이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if p_user_id is distinct from v_battle.creator_id
     and p_user_id is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  -- 참가할 때 확인했지만 그 사이 철회했을 수 있다. 동의 없이 사진이 AI로 나가면 안 된다.
  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  -- 판정 창이 열렸거나 종결됐으면 더 낼 수 없다. 마감만 지난 경우는 아래에서 따로 구분해 알린다.
  if v_battle.status <> 'active' then
    raise exception using message = '제출할 수 있는 상태가 아닙니다.', hint = 'SUBMISSION_LOCKED';
  end if;

  if v_battle.deadline_at is null or v_battle.deadline_at <= v_now then
    raise exception using message = '마감이 지났습니다.', hint = 'DEADLINE_PASSED';
  end if;

  -- 경로 위조 차단. Storage 정책과 같은 규칙을 서버에서 한 번 더 본다.
  if p_object_path not like (p_battle_id::text || '/' || p_user_id::text || '/%') then
    raise exception '사진 경로가 올바르지 않습니다.';
  end if;

  -- 대결이 시작되기 전에 찍어 둔 사진은 이 대결의 증거가 아니다.
  if v_battle.started_at is not null and p_captured_at < v_battle.started_at then
    raise exception using message = '대결 시작 전에 찍은 사진입니다.', hint = 'CAPTURED_BEFORE_START';
  end if;

  -- 촬영과 수신이 10분 이상 벌어지면 거부한다. 기기 시계가 앞선 경우도 같으므로 절댓값으로 본다.
  if abs(extract(epoch from (v_now - p_captured_at))) >= 600 then
    raise exception using message = '촬영 시각과 수신 시각이 너무 벌어졌습니다.', hint = 'CAPTURE_TIME_MISMATCH';
  end if;

  v_opponent_id := case
    when p_user_id = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  select * into v_my_submission from public.battle_submissions
  where battle_id = p_battle_id and user_id = p_user_id
  for update;

  select exists (
    select 1 from public.battle_submissions where battle_id = p_battle_id and user_id = v_opponent_id
  ) into v_opponent_submitted;

  if v_my_submission.id is not null then
    -- 이미 냈다. status가 여전히 active이므로 상대는 아직 내지 않았다(위 불변식).
    if v_battle.type <> 'speed' then
      raise exception using message = '이미 제출했습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    v_replaced_path := v_my_submission.object_path;

    update public.battle_submissions
    set object_path = p_object_path,
        captured_at = p_captured_at,
        submitted_at = v_now,
        meets_criteria = null,
        verdict_source = null,
        reason = null,
        ai_model = null
    where id = v_my_submission.id
    returning * into v_submission;
  else
    insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
    values (p_battle_id, p_user_id, p_object_path, p_captured_at, v_now)
    returning * into v_submission;

    update public.battle_participants
    set has_submitted = true
    where battle_id = p_battle_id and user_id = p_user_id;
  end if;

  v_gate := public.judging_gate(v_battle.type, true, v_opponent_submitted, false);

  if v_gate = 'open' then
    perform public.open_judging_window(p_battle_id);
    v_judging_opened := true;
  end if;

  return jsonb_build_object(
    'submission_id', v_submission.id,
    'replaced_object_path', v_replaced_path,
    'judging_opened', v_judging_opened,
    'battle_status', case when v_judging_opened then 'judging' else v_battle.status end
  );
end;
$$;

comment on function public.accept_submission is
  '증거 사진 제출(서버 전용). status=active인 동안 내 행이 있으면 교체(속도전만)로 덮어쓰고, '
  '없으면 새로 만든다. 양쪽이 모두 내면 같은 트랜잭션에서 판정 창을 연다. 시그니처 유지(배포된 '
  'submit-evidence가 이 시그니처로 부른다).';

-- 드롭 없이 create or replace였으므로 권한(service_role)은 그대로 유지된다.

-- ---------------------------------------------------------------------------
-- record_speed_verdict · sweep_stale_submissions 폐기
-- ---------------------------------------------------------------------------
-- 제출 즉시 AI 판정과 그 끊긴 동기 판정 정리가 사라진다. sweep_stale_submissions의 기준 생성
-- 정리 몫만 sweep_stale_criteria_calls로 옮긴다.
drop function public.record_speed_verdict(bigint, text, text, text);
drop function public.sweep_stale_submissions();

create function public.sweep_stale_criteria_calls()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_swept integer;
begin
  update public.ai_criteria_calls
  set status = 'failed'
  where status = 'in_progress'
    and created_at <= now() - interval '2 minutes';

  get diagnostics v_swept = row_count;
  return v_swept;
end;
$$;

comment on function public.sweep_stale_criteria_calls is
  '2분 넘게 in_progress인 기준 생성 호출을 failed로 정리한다(sweep_stale_submissions의 기준 생성 '
  '정리 몫을 옮긴 것). cron 전용.';

revoke execute on function public.sweep_stale_criteria_calls() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- cron: close-judging-windows 신규 등록, ai-judge-tick 명령 갱신
-- ---------------------------------------------------------------------------
select cron.schedule(
  'close-judging-windows',
  '* * * * *',
  $$select public.close_expired_judging_windows()$$
);

-- 같은 이름으로 다시 부르면 기존 작업이 갱신된다(중복 등록이 아니다, ai-judge 6단계 선례).
-- dispatch_quality_judgments는 아직 지우지 않았다(3단계 몫) — 이제 잡이 생기지 않으므로
-- 할 일이 없어 매번 즉시 반환한다.
select cron.schedule(
  'ai-judge-tick',
  '* * * * *',
  $$select public.sweep_stale_criteria_calls(); select public.dispatch_quality_judgments();$$
);
