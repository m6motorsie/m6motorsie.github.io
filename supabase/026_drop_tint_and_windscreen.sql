-- =====================================================================
-- M6 Motors — "Window Tint / Dechrome" and "Windscreen" are no longer job
-- bubbles (the team logs them with the 🔧 work log instead).
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- Takes them off every car's list of jobs and off everyone's jobs on the Team
-- screen, so cars aren't kept waiting for them ("All services done" and the
-- move to Deliveries count only the jobs a car still has). Old records stay.

update public.vehicles
set services = array_remove(array_remove(services, 'decrome'), 'windscreen')
where services && array['decrome', 'windscreen'];

update public.profiles
set services = array_remove(array_remove(services, 'decrome'), 'windscreen')
where services && array['decrome', 'windscreen'];

-- Check: both should be 0
select
  (select count(*) from public.vehicles where services && array['decrome', 'windscreen']) as cars_still_with_them,
  (select count(*) from public.profiles where services && array['decrome', 'windscreen']) as people_still_with_them;
