-- Finds a user to invite as a companion. Returns only id and name.
create or replace function public.find_profile_by_email(lookup_email text)
returns table (id uuid, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name
    from public.profiles p
   where (select auth.uid()) is not null
     and p.email = lower(trim(lookup_email))
   limit 1;
$$;

revoke execute on function public.find_profile_by_email(text) from public, anon;
revoke execute on function public.is_caregiver_of(uuid) from public, anon;
grant execute on function public.find_profile_by_email(text) to authenticated;
grant execute on function public.is_caregiver_of(uuid) to authenticated;

-- Trigger functions are not meant to be called directly.
revoke execute on function public.keep_newest_and_touch() from public, anon, authenticated;
revoke execute on function public.guard_companion_link() from public, anon, authenticated;
