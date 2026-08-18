-- battles: 2인 대결. 유형은 speed(속도전) / quality(품질전) 두 가지뿐.
create table public.battles (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('speed', 'quality')),
  status text not null default 'pending'
    check (status in ('pending', 'active', 'judging', 'finished', 'disputed')),
  title text not null,
  creator_id uuid not null references auth.users (id) on delete cascade,
  opponent_id uuid not null references auth.users (id) on delete cascade,
  winner_id uuid references auth.users (id),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  constraint battles_distinct_players check (creator_id <> opponent_id)
);

create index battles_creator_id_idx on public.battles (creator_id);
create index battles_opponent_id_idx on public.battles (opponent_id);

alter table public.battles enable row level security;

-- 상태 전이는 전부 SECURITY DEFINER 함수(judging 로직)를 통해서만 이뤄진다.
-- 클라이언트가 status/winner_id를 직접 UPDATE할 수 있는 정책은 두지 않는다.
create policy "participants can view their battles"
  on public.battles for select
  to authenticated
  using (auth.uid() in (creator_id, opponent_id));

create policy "creator can create a pending battle"
  on public.battles for insert
  to authenticated
  with check (auth.uid() = creator_id and status = 'pending');

-- battle_participants: 대결 1건당 참가자 2명, 각자의 진행 상황을 담는다.
-- speed: completed_at만 사용. quality: evidence_*, decision_*까지 사용.
-- decision/decision_at은 "이 행의 user_id 본인"이 아니라 "상대방"이 이 증거를 검토한 결과다.
create table public.battle_participants (
  battle_id uuid not null references public.battles (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  completed_at timestamptz,
  evidence_type text check (evidence_type in ('photo', 'text')),
  evidence_content text,
  evidence_submitted_at timestamptz,
  decision text check (decision in ('approve', 'dispute')),
  decision_at timestamptz,
  primary key (battle_id, user_id)
);

alter table public.battle_participants enable row level security;

-- 이 테이블도 client UPDATE/INSERT 정책 없음 - RPC 함수로만 변경.
create policy "participants can view their battle progress"
  on public.battle_participants for select
  to authenticated
  using (
    exists (
      select 1 from public.battles b
      where b.id = battle_id and auth.uid() in (b.creator_id, b.opponent_id)
    )
  );
