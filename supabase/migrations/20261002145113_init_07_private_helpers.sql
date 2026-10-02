-- Policy helpers do not need to be callable through the REST API, so they
-- live in a schema that PostgREST does not expose. Policies reference the
-- functions by id, so moving them keeps the policies working.
create schema if not exists private;
grant usage on schema private to authenticated;
alter function public.is_caregiver_of(uuid) set schema private;
alter function public.can_access_owner_folder(text) set schema private;
