create table calibration_profiles (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references auth.users not null,
  name             text not null,
  profile_id       integer,
  slot             integer,
  quality          integer default 0,
  ref_x            double precision default 0,
  ref_y            double precision default 0,
  ref_z            double precision default 0,
  total_samples    integer default 0,
  passed_samples   integer default 0,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  unique (user_id, name)
);

create index on calibration_profiles (user_id, updated_at desc);

alter table calibration_profiles enable row level security;

create policy "own calibration profiles" on calibration_profiles
  for all using (auth.uid() = user_id);