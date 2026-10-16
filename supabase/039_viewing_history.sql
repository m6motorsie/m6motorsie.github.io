-- =====================================================================
-- M6 Motors — viewings clear themselves and go on the car's work log
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- 1. When a viewing is taken off a car ("Viewing done", "Clear past", or the
--    night clean-up below), a line goes on the car's work log, e.g.
--    "👀 Viewing · Thu 15 Oct 14:00 · booked by Derek · refreshed by Yann".
--    So nothing is lost, and the app can count viewings per week / month.
-- 2. Every night just after midnight (Dublin), viewings from before today are
--    taken off by themselves (pg_cron, like the 8am sold-cars summary).

create or replace function public.vehicles_viewing_to_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.viewing_at is not null and new.viewing_at is null then
    insert into vehicle_work_log (vehicle_id, note, created_by)
    values (
      new.id,
      '👀 Viewing · ' || to_char(old.viewing_at at time zone 'Europe/Dublin', 'Dy DD Mon HH24:MI')
        || coalesce(' · booked by ' || (select display_name from profiles where id = old.viewing_by), '')
        || case when old.refresh_state = 'done'
                then coalesce(' · refreshed by ' || (select display_name from profiles where id = old.refresh_by), ' · refreshed')
                else '' end
        || case when btrim(coalesce(old.viewing_note, '')) <> '' then ' — ' || btrim(old.viewing_note) else '' end,
      old.viewing_by);
  end if;
  return null;
end $$;

drop trigger if exists vehicles_viewing_to_log on public.vehicles;
create trigger vehicles_viewing_to_log after update of viewing_at on public.vehicles
  for each row execute function public.vehicles_viewing_to_log();

-- Viewings from before today (Dublin time) come off by themselves
create or replace function public.clear_past_viewings() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  update vehicles set viewing_at = null
  where viewing_at is not null
    and viewing_at < (date_trunc('day', now() at time zone 'Europe/Dublin') at time zone 'Europe/Dublin');
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.clear_past_viewings() from public, anon, authenticated;

create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule('m6-clear-viewings');
exception when others then null;
end $$;

-- 00:15 and 01:15 UTC = just after midnight in Dublin, summer and winter time
select cron.schedule('m6-clear-viewings', '15 0,1 * * *', $$select public.clear_past_viewings()$$);

-- Clear the old ones now (the number = how many came off)
select public.clear_past_viewings() as viewings_cleared;
