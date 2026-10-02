-- exercise_videos: catalogue of exercise videos shown on the Discover tab.
-- Files live in the public Storage bucket `exercise-videos`; rows store the
-- path inside that bucket. Public SELECT of active rows; writes are admin-only
-- via the Supabase dashboard or service-role key.

create table if not exists public.exercise_videos (
  id            uuid        primary key default gen_random_uuid(),
  title         text        not null,
  description   text        not null default '',
  category      text        not null default '',
  duration_sec  int         not null default 0,
  video_path    text        not null,
  thumb_path    text,
  sort_order    int         not null default 0,
  active        boolean     not null default true,
  created_at    timestamptz not null default now()
);

alter table public.exercise_videos enable row level security;

create policy "Public can read active exercise videos"
  on public.exercise_videos
  for select
  using (active);
