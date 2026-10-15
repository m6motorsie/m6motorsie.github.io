-- =====================================================================
-- M6 Motors — Delivered by the sales team; Full Valet drops the First Clean
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- 1. Only the sales team (profiles.can_testdrive: Alan, Eanna, Derek) can mark
--    a car delivered (and undo it). Reopening an old delivery stays possible
--    for admins too.
-- 2. When a Full Valet is finished on a car whose First Clean nobody started,
--    the app takes First Clean off the car's jobs (it isn't needed any more,
--    and it isn't credited to anyone). Staff may make that one change to
--    vehicles.services; everything else there stays managers-only (032).

create or replace function public.vehicles_deliver_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null then return new; end if;
  if new.status = 'delivered' and old.status is distinct from 'delivered'
     and not public.can_testdrive() then
    raise exception 'Only the sales team can mark a car delivered' using errcode = '42501';
  end if;
  if old.status = 'delivered' and new.status is distinct from 'delivered'
     and not (public.can_testdrive() or public.is_admin()) then
    raise exception 'Only the sales team or a manager can reopen a delivered car' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists vehicles_deliver_guard on public.vehicles;
create trigger vehicles_deliver_guard before update on public.vehicles
  for each row execute function public.vehicles_deliver_guard();

create or replace function public.vehicles_services_guard() returns trigger
language plpgsql as $$
declare
  k text;
  drops_first boolean;
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  -- Full Valet finished now, First Clean never started: it may be taken off
  drops_first := 'first' = any(old.services)
    and new.services = array_remove(old.services, 'first')
    and old.first_state = 'pending' and new.first_state = 'pending'
    and new.full_state = 'done' and old.full_state is distinct from 'done';
  if new.services is distinct from old.services and not drops_first then
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
