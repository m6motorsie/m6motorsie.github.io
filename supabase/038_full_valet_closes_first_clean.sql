-- =====================================================================
-- M6 Motors — a finished Full Valet always closes the First Clean
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- When the Full Valet is marked done, a First Clean that isn't done (not
-- started, or started and left in progress) is taken off the car's jobs:
-- the Full Valet covered it. It isn't credited to anyone. The database does
-- this itself, so it works whoever finishes the Full Valet.
--
-- The trigger name sorts after vehicles_guard and vehicles_services_guard
-- (Postgres runs BEFORE triggers in name order), so the staff checks have
-- already passed, and before vehicles_urgent_off_when_done, so URGENT also
-- comes off when this makes the car all done.
--
-- At the end: cars already in that state are fixed, and URGENT is taken off
-- cars whose jobs are all done (URGENT only means "clean this one first").

create or replace function public.vehicles_tidy_first_after_full() returns trigger
language plpgsql as $$
begin
  if new.full_state = 'done' and old.full_state is distinct from 'done'
     and 'first' = any(new.services) and new.first_state is distinct from 'done' then
    new.services      := array_remove(new.services, 'first');
    new.first_state   := 'pending';
    new.first_by      := null;
    new.first_done_at := null;
    -- all the car's remaining jobs done? (vehicles_guard worked it out before First Clean went)
    if not exists (select 1 from unnest(new.services) s
                   where to_jsonb(new) ->> (s || '_state') is distinct from 'done') then
      new.done_at := coalesce(old.done_at, now());
    end if;
  end if;
  return new;
end $$;

drop trigger if exists vehicles_tidy_first_after_full on public.vehicles;
create trigger vehicles_tidy_first_after_full before update on public.vehicles
  for each row execute function public.vehicles_tidy_first_after_full();

-- Fix the cars already like that: Full Valet done, First Clean still open
update public.vehicles
set services = array_remove(services, 'first'),
    first_state = 'pending', first_by = null, first_done_at = null
where status <> 'delivered'
  and full_state = 'done'
  and 'first' = any(services)
  and first_state is distinct from 'done';

-- URGENT off on cars whose jobs are all done (sold cars: also those with no jobs)
update public.vehicles
set urgent = false
where urgent
  and status <> 'delivered'
  and done_at is not null
  and (status = 'in_prep' or cardinality(services) > 0);

-- What's left with URGENT (should only be cars still waiting for a job)
select coalesce(nullif(reg_ie, ''), reg_imp) as plate, make, model, status, services, done_at
from public.vehicles where urgent and status <> 'delivered' order by created_at;
