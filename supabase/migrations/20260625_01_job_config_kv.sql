-- Small key/value JSONB store for job state (rotation cursors, etc.).
-- Written by backend jobs only (service role). See scheduler.py NEWS_ROTATION_CURSOR_KEY.
create table if not exists public.job_config (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
comment on table public.job_config is 'Key/value JSONB store for job state (e.g. news rotation cursor). Backend-only.';
