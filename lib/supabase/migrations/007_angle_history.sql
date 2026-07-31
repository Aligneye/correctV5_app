create table angle_history (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete cascade,
  time timestamptz not null,
  deviation float not null,
  ref_angle float not null,
  created_at timestamptz default now()
);

alter table angle_history enable row level security;

create policy "Users see own angle history"
  on angle_history for all
  using (auth.uid() = user_id);