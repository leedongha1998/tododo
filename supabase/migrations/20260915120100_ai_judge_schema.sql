-- ai-judge 1단계: AI 판정·점수를 담을 스키마 기반.
--
-- 근거: docs/specs/ai-judge/design.md "상태 전이", "점수와 outcome", "테이블 변경".
-- 이 파일은 AI에 의존하지 않는 부분만 담는다. 기준(min_criteria 등)은 3단계,
-- 품질전 판정 잡·verdict_reason은 6단계, Storage 정책 교체는 5단계에서 추가한다.
-- 직전 마이그레이션(20260915120000_ai_judge_reset)이 battles를 비웠다는 전제로 제약을 건다.

-- ---------------------------------------------------------------------------
-- battles: voided(무효) 상태 추가
-- ---------------------------------------------------------------------------
-- voided는 "AI 판정이 실패해 끝났다"이다. draw(시간 종료, -1점, 공개 전적 포함)나
-- cancelled(모집 취소·탈퇴 정리, 기록 목록에 안 나옴)와 성질이 달라 합치지 않는다.
-- disputed는 배포 후 유료 재심을 위해 값만 남긴다. MVP의 어떤 함수도 이 값을 쓰지 않는다.
alter table public.battles
  drop constraint battles_status_check,
  add constraint battles_status_check
    check (status in ('pending', 'active', 'judging', 'finished', 'disputed', 'cancelled', 'draw', 'voided'));

-- 품질전에도 승자를 두므로 finished는 항상 승자가 있다(포기 포함). 이 불변식을 DB가 강제한다.
alter table public.battles
  add constraint battles_finished_has_winner
    check (status <> 'finished' or winner_id is not null);

comment on column public.battles.status is
  'pending(모집 중) -> active(매칭됨) -> [judging(품질전 AI 판정 대기)] -> finished(승자 있음) | draw | voided(AI 판정 실패) | cancelled. disputed는 유료 재심용 개념으로만 남고 MVP에서 도달하지 않는다.';

-- ---------------------------------------------------------------------------
-- battle_participants: 증거·상호 판정 컬럼 제거, 진행 요약·결과 컬럼 추가
-- ---------------------------------------------------------------------------
-- 이 테이블은 참가자 둘 다 읽을 수 있다. 그래서 진행 중에 상대에게 보여도 되는 요약만 둔다.
-- 사진 경로와 판정 사유는 battle_submissions(RLS로 종결 전 상대에게 가림)에 둔다.
alter table public.battle_participants
  drop column evidence_type,
  drop column evidence_content,
  drop column evidence_submitted_at,
  drop column decision,
  drop column decision_at;

alter table public.battle_participants
  add column first_submitted_at timestamptz,
  add column attempts_used smallint not null default 0,
  add column last_verdict text
    constraint battle_participants_last_verdict_check check (last_verdict in ('passed', 'failed')),
  add column passed_at timestamptz,
  add column outcome text
    constraint battle_participants_outcome_check
      check (outcome in ('win', 'completed_loss', 'loss', 'forfeit', 'draw')),
  add column score_delta_applied smallint;

comment on column public.battle_participants.first_submitted_at is
  '처음으로 수락된 제출의 서버 시각. 상대에게 "제출했어요"를 알리는 표시용이며 승부에는 쓰지 않는다.';
comment on column public.battle_participants.attempts_used is
  '속도전 AI 판정 사용 횟수(passed + failed). error와 거부된 사진은 세지 않는다. 표시용 요약이며 규칙 계산은 battle_submissions 원본으로 한다.';
comment on column public.battle_participants.last_verdict is
  '속도전 최근 판정 결과. 사유 없이 합격/불합격만 담아 진행 중 상대에게 보여도 된다.';
comment on column public.battle_participants.passed_at is
  '속도전 최소 기준을 통과한 제출의 서버 시각. 승부 기준 시각.';
comment on column public.battle_participants.outcome is
  '종결 시 finalize_battle이 기록하는 결과. 점수 변화와 승/패/무 집계가 모두 이 값에서 나온다. voided/cancelled는 null.';
comment on column public.battle_participants.score_delta_applied is
  '점수 하한 0을 적용한 뒤 실제로 바뀐 점수. 결과 화면 표시용.';

-- ---------------------------------------------------------------------------
-- battle_submissions: 증거 제출 원장 (신규)
-- ---------------------------------------------------------------------------
-- 제출마다 한 행. 거부된 사진(매칭 전 촬영, 10분 차이, 마감 후)은 행을 만들지 않는다.
-- 쓰기는 5·6단계의 서버 전용 함수만 한다(insert/update/delete 정책 없음).
create table public.battle_submissions (
  id bigserial primary key,
  battle_id uuid not null references public.battles (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  object_path text,
  captured_at timestamptz not null,
  submitted_at timestamptz not null default now(),
  status text not null
    constraint battle_submissions_status_check
      check (status in ('judging', 'passed', 'failed', 'error', 'submitted')),
  judging_started_at timestamptz,
  reason text,
  meets_criteria boolean,
  ai_model text
);

comment on table public.battle_submissions is
  '증거 사진 제출 원장. 속도전: judging -> passed | failed | error. 품질전: submitted. 진행 중에는 본인 행만 보이고, 종결 뒤에 상대 행(사진 경로·사유)이 열린다.';
comment on column public.battle_submissions.object_path is
  'battle_evidence 버킷 경로 {battle_id}/{user_id}/{uuid}.jpg. 탈퇴하면 null.';
comment on column public.battle_submissions.captured_at is
  '앱이 보낸 촬영 시각. 거부 판단(대조)에만 쓰고 승부와 AI 전송에는 쓰지 않는다.';
comment on column public.battle_submissions.submitted_at is
  '서버 수신 시각. 속도전 승부 기준.';

create index battle_submissions_battle_user_idx
  on public.battle_submissions (battle_id, user_id);

-- 참가자당 판정 중인 제출 1개, 통과 1회, 품질전 제출 1회.
create unique index battle_submissions_one_judging_idx
  on public.battle_submissions (battle_id, user_id) where status = 'judging';
create unique index battle_submissions_one_passed_idx
  on public.battle_submissions (battle_id, user_id) where status = 'passed';
create unique index battle_submissions_one_quality_idx
  on public.battle_submissions (battle_id, user_id) where status = 'submitted';

alter table public.battle_submissions enable row level security;

-- 내 제출은 언제든, 상대 제출은 대결이 종결된 뒤에만(베끼기 방지, spec 결정 20·65).
create policy "users can view own submissions or finished battle submissions"
  on public.battle_submissions for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.battles b
      where b.id = battle_id
        and b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed')
        and (b.creator_id = auth.uid() or b.opponent_id = auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- player_stats: 점수·전적 (신규)
-- ---------------------------------------------------------------------------
-- profiles에 두지 않는 이유: profiles는 모든 authenticated가 읽을 수 있어 임의 사용자 전적 조회가
-- 생기고(spec 위반), 본인 update 정책이 있어 점수를 스스로 고칠 수 있게 된다.
create table public.player_stats (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  score integer not null default 0 constraint player_stats_score_floor check (score >= 0),
  wins integer not null default 0 constraint player_stats_wins_check check (wins >= 0),
  losses integer not null default 0 constraint player_stats_losses_check check (losses >= 0),
  draws integer not null default 0 constraint player_stats_draws_check check (draws >= 0)
);

comment on table public.player_stats is
  '점수와 승/패/무 카운터. 쓰기는 finalize_battle만. 무효·취소는 반영하지 않는다.';

alter table public.player_stats enable row level security;

-- 다른 사용자의 전적은 4단계 get_player_card RPC가 허용 범위(대결 상대·모집 생성자)만 내준다.
create policy "users can view their own stats"
  on public.player_stats for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- daily_battle_slots: 하루 1대결 원장 (신규)
-- ---------------------------------------------------------------------------
-- 매칭되는 순간(4단계 join_battle) 양쪽에 KST 날짜로 한 행씩 넣는다. PK가 하루 2개를 물리적으로 막는다.
-- 무효·탈퇴 취소 시 "매칭된 날이 오늘"인 행만 지워 오늘 한도를 돌려준다.
create table public.daily_battle_slots (
  user_id uuid not null references public.profiles (id) on delete cascade,
  kst_date date not null,
  battle_id uuid not null references public.battles (id) on delete cascade,
  primary key (user_id, kst_date)
);

create index daily_battle_slots_battle_idx on public.daily_battle_slots (battle_id);

comment on table public.daily_battle_slots is
  '하루(KST) 매칭 대결 1개 한도 원장. kst_date는 매칭된 날.';

alter table public.daily_battle_slots enable row level security;

create policy "users can view their own daily slots"
  on public.daily_battle_slots for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 가입 시 점수 행 생성 + 기존 사용자 백필
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email));

  insert into public.player_stats (user_id) values (new.id);

  return new;
end;
$$;

-- create or replace는 권한을 유지하지만 트리거 전용 함수라는 점을 한 번 더 못박는다.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- 탈퇴한 사용자(묘비)의 점수는 공개 대상이 아니므로 만들지 않는다.
insert into public.player_stats (user_id)
select id from public.profiles where deleted_at is null
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------------
-- 상호 승인 RPC 폐기
-- ---------------------------------------------------------------------------
-- submit_evidence는 5단계에서 Edge Function(submit-evidence) + accept_submission으로 대체된다.
-- decide_evidence는 참가자 판정 자체가 없어지므로 대체가 없다.
drop function if exists public.submit_evidence(uuid, text, text);
drop function if exists public.decide_evidence(uuid, uuid, text);
