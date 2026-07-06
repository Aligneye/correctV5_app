-- XP and level system for AlignEye gamification
-- Mirrors user_streaks pattern with RLS

create table user_xp (
  user_id      uuid primary key references auth.users,
  total_xp     integer not null default 0,
  current_level integer not null default 1,
  updated_at   timestamptz default now()
);

alter table user_xp enable row level security;

create policy "own xp" on user_xp
  for all using (auth.uid() = user_id);

-- Add freeze_tokens to user_streaks (Feature 2 migration included here)
alter table user_streaks
  add column if not exists freeze_tokens integer not null default 2,
  add column if not exists freeze_used_days jsonb not null default '[]'::jsonb;
