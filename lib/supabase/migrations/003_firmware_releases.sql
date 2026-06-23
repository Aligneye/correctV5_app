-- firmware_releases: stores published firmware versions served to the app.
-- Public SELECT is allowed (no auth required) so unauthenticated users can
-- still receive updates. All writes are admin-only via the Supabase dashboard
-- or service-role key.

create table if not exists public.firmware_releases (
  id                        uuid primary key default gen_random_uuid(),
  latest_version            text        not null,
  build_number              integer     not null,
  device_model              text        not null default '',
  hardware_revision         text        not null default '',
  min_supported_app_version text        not null default '1.0.0',
  min_battery_percent       integer     not null default 40,
  mandatory                 boolean     not null default false,
  firmware_url              text        not null,
  sha256                    text        not null,
  file_size_bytes           integer     not null default 0,
  release_notes             jsonb       not null default '[]'::jsonb,
  active                    boolean     not null default true,
  created_at                timestamptz not null default now()
);

-- Index used by fetchManifest: active rows ordered by build_number desc, limit 1.
create index if not exists firmware_releases_active_build_idx
  on public.firmware_releases (build_number desc)
  where active = true;

-- RLS: enable but allow public SELECT.
alter table public.firmware_releases enable row level security;

create policy "Public can read active firmware releases"
  on public.firmware_releases
  for select
  using (true);
