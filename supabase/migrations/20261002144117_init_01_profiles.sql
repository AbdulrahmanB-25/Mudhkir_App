-- Mudhkir cloud schema.
--
-- The phone is the source of truth (SQLite). These tables are the backup and
-- the shared space for caregivers. Columns mirror lib/data/sync/sync_codecs.dart.
--
-- Sync rules:
--  * Every row carries the client's `updated_at`; an upsert with an OLDER
--    `updated_at` than the stored row is ignored (newest edit wins).
--  * `synced_at` is set by the server on every accepted write; clients pull
--    rows with `synced_at` > their last checkpoint.
--  * Rows are soft-deleted (`deleted_at`) so deletions sync too.

-- ---------------------------------------------------------------- helpers

create or replace function public.keep_newest_and_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    -- A late, older change: keep the newer row.
    return null;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end;
$$;

-- ---------------------------------------------------------------- profiles

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  email text,
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
comment on table public.profiles is 'Display name and email of each user (one row per auth user).';

create index profiles_email_idx on public.profiles (email);
create index profiles_synced_at_idx on public.profiles (synced_at);

create trigger profiles_keep_newest
before insert or update on public.profiles
for each row execute function public.keep_newest_and_touch();

alter table public.profiles enable row level security;

create policy "profiles: read own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profiles: insert own" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
