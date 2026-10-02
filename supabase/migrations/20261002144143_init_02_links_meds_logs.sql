-- ---------------------------------------------------------------- companion links

create table public.companion_links (
  id text primary key,
  caregiver_id uuid not null references auth.users (id) on delete cascade,
  patient_id uuid not null references auth.users (id) on delete cascade,
  caregiver_name text,
  patient_name text,
  patient_email text,
  relationship text,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default now(),
  constraint companion_links_not_self check (caregiver_id <> patient_id)
);
comment on table public.companion_links is
  'A caregiver following a patient''s medications. The patient must accept.';

create unique index companion_links_active_pair
  on public.companion_links (caregiver_id, patient_id)
  where deleted_at is null;
create index companion_links_patient_idx on public.companion_links (patient_id);
create index companion_links_synced_at_idx on public.companion_links (synced_at);

create trigger companion_links_keep_newest
before insert or update on public.companion_links
for each row execute function public.keep_newest_and_touch();

-- Only the patient decides whether a link is accepted, and the people on a
-- link can never be swapped.
create or replace function public.guard_companion_link()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    if uid is not null and uid = new.caregiver_id then
      new.status := 'pending';
    end if;
    return new;
  end if;
  if new.caregiver_id <> old.caregiver_id or new.patient_id <> old.patient_id then
    raise exception 'companion link members cannot change';
  end if;
  if uid is not null and uid <> old.patient_id then
    new.status := old.status;
  end if;
  return new;
end;
$$;

create trigger companion_links_guard
before insert or update on public.companion_links
for each row execute function public.guard_companion_link();

-- True when the current user is an accepted caregiver of [patient].
create or replace function public.is_caregiver_of(patient uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.companion_links l
     where l.patient_id = patient
       and l.caregiver_id = (select auth.uid())
       and l.status = 'accepted'
       and l.deleted_at is null
  );
$$;

-- ---------------------------------------------------------------- medications

create table public.medications (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  dosage_amount text not null,
  dosage_unit text not null,
  frequency text not null check (frequency in ('daily', 'weekly')),
  times jsonb not null default '[]'::jsonb,
  start_date date not null,
  end_date date,
  ended_at timestamptz,
  notes text,
  image_remote_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default now()
);
comment on table public.medications is 'Medications and their reminder times.';

create index medications_owner_idx on public.medications (owner_id);
create index medications_synced_at_idx on public.medications (synced_at);

create trigger medications_keep_newest
before insert or update on public.medications
for each row execute function public.keep_newest_and_touch();

-- ---------------------------------------------------------------- dose logs

create table public.dose_logs (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  medication_id text not null references public.medications (id) on delete cascade,
  scheduled_at timestamptz not null,
  status text not null check (status in ('taken', 'skipped', 'rescheduled')),
  acted_at timestamptz not null,
  rescheduled_to timestamptz,
  acted_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default now()
);
comment on table public.dose_logs is 'Taken / skipped / rescheduled records, one per scheduled dose.';

create index dose_logs_owner_idx on public.dose_logs (owner_id, scheduled_at);
create index dose_logs_medication_idx on public.dose_logs (medication_id);
create index dose_logs_acted_by_idx on public.dose_logs (acted_by);
create index dose_logs_synced_at_idx on public.dose_logs (synced_at);

create trigger dose_logs_keep_newest
before insert or update on public.dose_logs
for each row execute function public.keep_newest_and_touch();

-- Row level security
alter table public.companion_links enable row level security;
alter table public.medications enable row level security;
alter table public.dose_logs enable row level security;

create policy "links: read either side" on public.companion_links
  for select to authenticated
  using ((select auth.uid()) in (caregiver_id, patient_id));
create policy "links: caregiver invites" on public.companion_links
  for insert to authenticated
  with check (caregiver_id = (select auth.uid()) and status = 'pending');
create policy "links: update either side" on public.companion_links
  for update to authenticated
  using ((select auth.uid()) in (caregiver_id, patient_id))
  with check ((select auth.uid()) in (caregiver_id, patient_id));

create policy "medications: owner or caregiver reads" on public.medications
  for select to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)));
create policy "medications: owner or caregiver adds" on public.medications
  for insert to authenticated
  with check (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)));
create policy "medications: owner or caregiver edits" on public.medications
  for update to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)))
  with check (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)));

create policy "dose logs: owner or caregiver reads" on public.dose_logs
  for select to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)));
create policy "dose logs: owner or caregiver adds" on public.dose_logs
  for insert to authenticated
  with check (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)));
create policy "dose logs: owner or caregiver edits" on public.dose_logs
  for update to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)))
  with check (owner_id = (select auth.uid()) or (select public.is_caregiver_of(owner_id)));

-- No delete policies: rows are soft-deleted; deleting the account cascades.
