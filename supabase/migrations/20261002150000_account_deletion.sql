-- Account deletion (required by the App Store for apps with sign-up).
--
-- NOT applied automatically: run this once in the Supabase dashboard
-- (SQL Editor) or with `supabase db push`. See RUNNING.md.
-- Permanently deletes the caller's account and all of their data.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = uid;
end;
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

create policy "medication images: delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'medication-images'
         and (select private.can_access_owner_folder((storage.foldername(name))[1])));
