-- firmware_releases: stores published firmware versions served to the app.
-- Public SELECT is allowed (no auth required) so unauthenticated users can
-- still receive updates. All writes are admin-only via the Supabase dashboard
-- or service-role key.

create table if not exists public.firmware_releases (
  id                        uuid primary key default gen_random_uuid(),
  firmware_version          text,
  app_version               text        not null,
  device_model              text        not null default '',
  hardware_revision         text        not null default '',
  mandatory                 boolean     not null default false,
  firmware_url              text        not null,
  sha256                    text        not null,
  release_notes             jsonb       not null default '[]'::jsonb,
  "Active"                  boolean     not null default true,
  github_tag                text,
  github_release_url        text,
  created_at                timestamptz not null default now()
);

-- Index used by fetchManifest: active rows ordered by created_at desc, limit 1.
create index if not exists firmware_releases_active_created_idx
  on public.firmware_releases (created_at desc)
  where "Active" = true;

-- RLS: enable but allow public SELECT.
alter table public.firmware_releases enable row level security;

create policy "Public can read active firmware releases"
  on public.firmware_releases
  for select
  using (true);