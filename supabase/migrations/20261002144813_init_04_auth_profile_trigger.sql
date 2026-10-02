-- Creates the profile when someone signs up and keeps the email current.
create or replace function public.handle_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.profiles (id, name, email, updated_at)
    values (
      new.id,
      coalesce(new.raw_user_meta_data ->> 'name', ''),
      lower(new.email),
      now()
    )
    on conflict (id) do nothing;
  elsif new.email is distinct from old.email then
    update public.profiles
       set email = lower(new.email), updated_at = now()
     where id = new.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.handle_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_auth_user();

create trigger on_auth_user_email_changed
after update of email on auth.users
for each row execute function public.handle_auth_user();
