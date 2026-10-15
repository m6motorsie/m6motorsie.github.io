-- =====================================================================
-- M6 Motors — URGENT comes off when the car's jobs are all done
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- "Urgent" means "clean this one first". When the last job on the car is
-- finished (done_at gets set by vehicles_guard), the flag is cleared, so a
-- car sold on arrival goes to Deliveries without the red URGENT.
-- The trigger name sorts after vehicles_guard, so done_at is already worked
-- out when it runs.

create or replace function public.vehicles_urgent_off_when_done() returns trigger
language plpgsql as $$
begin
  if new.urgent and new.done_at is not null and old.done_at is null
     and cardinality(new.services) > 0 then
    new.urgent := false;
  end if;
  return new;
end $$;

drop trigger if exists vehicles_urgent_off_when_done on public.vehicles;
create trigger vehicles_urgent_off_when_done before update on public.vehicles
  for each row execute function public.vehicles_urgent_off_when_done();
