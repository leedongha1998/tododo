-- profiles: 1 row per auth.users, created automatically on signup (Google 로그인 1종)
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are viewable by any authenticated user"
  on public.profiles for select
  to authenticated
  using (true);

create policy "users can update their own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- auth.users에 새 계정이 생기면 profiles 행을 자동 생성한다.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- todos: 개인 투두 (대결과 별개)
create table public.todos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  is_done boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index todos_user_id_idx on public.todos (user_id);

alter table public.todos enable row level security;

create policy "users can view their own todos"
  on public.todos for select
  to authenticated
  using (auth.uid() = user_id);

create policy "users can insert their own todos"
  on public.todos for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users can update their own todos"
  on public.todos for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users can delete their own todos"
  on public.todos for delete
  to authenticated
  using (auth.uid() = user_id);

create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger todos_set_updated_at
  before update on public.todos
  for each row execute function public.set_updated_at();
