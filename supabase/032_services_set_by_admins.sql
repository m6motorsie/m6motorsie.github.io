-- =====================================================================
-- M6 Motors — only managers decide which jobs a car needs
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- The jobs a car needs (vehicles.services) are chosen when it's added or
-- edited by an admin. Staff can only work on those jobs: they can't add a job
-- to a car, or start one that wasn't asked for.

create or replace function public.vehicles_services_guard() returns trigger
language plpgsql as $$
declare
  k text;
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if new.services is distinct from old.services then
    raise exception 'Only managers can change the jobs a car needs' using errcode = '42501';
  end if;
  foreach k in array public.service_keys() loop
    if not (k = any(new.services))
       and (to_jsonb(new) ->> (k || '_state')) is distinct from (to_jsonb(old) ->> (k || '_state')) then
      raise exception 'That job wasn''t asked for on this car' using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists vehicles_services_guard on public.vehicles;
create trigger vehicles_services_guard before update on public.vehicles
  for each row execute function public.vehicles_services_guard();
