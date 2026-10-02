-- ---------------------------------------------------------------- storage

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'medication-images',
  'medication-images',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do nothing;

-- Paths are `{owner_id}/{medication_id}/{file}`.
create or replace function public.can_access_owner_folder(folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select folder = (select auth.uid())::text
      or exists (
        select 1
          from public.companion_links l
         where l.patient_id::text = folder
           and l.caregiver_id = (select auth.uid())
           and l.status = 'accepted'
           and l.deleted_at is null
      );
$$;
revoke execute on function public.can_access_owner_folder(text) from public, anon;
grant execute on function public.can_access_owner_folder(text) to authenticated;

create policy "medication images: read" on storage.objects
  for select to authenticated
  using (bucket_id = 'medication-images'
         and (select public.can_access_owner_folder((storage.foldername(name))[1])));
create policy "medication images: upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'medication-images'
              and (select public.can_access_owner_folder((storage.foldername(name))[1])));
create policy "medication images: replace" on storage.objects
  for update to authenticated
  using (bucket_id = 'medication-images'
         and (select public.can_access_owner_folder((storage.foldername(name))[1])));
