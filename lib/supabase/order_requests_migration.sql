-- order_requests table: stores pre-order interest from both app and website
-- Webhook on INSERT triggers Edge Function → Resend email to customer

create table order_requests (
  id               uuid primary key default gen_random_uuid(),
  full_name        text not null,
  email            text not null,
  phone            text,
  quantity         integer not null default 1,
  delivery_address text,
  notes            text,
  source           text default 'app' check (source in ('app', 'website')),
  created_at       timestamptz default now()
);

-- Public insert: unauthenticated users (guests) can also submit orders
alter table order_requests enable row level security;

create policy "anyone can insert order_requests" on order_requests
  for insert with check (true);

-- Admins read all (add admin role as needed)
create policy "service role reads all" on order_requests
  for select using (auth.role() = 'service_role');
