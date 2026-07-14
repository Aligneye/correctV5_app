create table user_disclaimer_acceptances (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references auth.users not null,
  disclaimer_version  integer not null,
  accepted_at         timestamptz not null default now(),
  created_at          timestamptz default now()
);

create unique index on user_disclaimer_acceptances (user_id, disclaimer_version);

alter table user_disclaimer_acceptances enable row level security;

create policy "own disclaimer acceptances" on user_disclaimer_acceptances
  for all using (auth.uid() = user_id);
