-- M6 Motors — battery on hybrid and electric cars.
-- Run after 051_mat_stock.sql. Safe to run again.
--
-- Hybrids and electrics sitting on the lot go flat. A manager marks a car as
-- Hybrid / Plug-in hybrid / Electric (car form); those cars get a battery icon
-- next to the plate that ANYONE on staff can tap: Full / Half / Low / Flat.
--   • who checked it and when are stamped here, not by the phone
--   • every check goes on the car's 🔧 work log ("🔋 Battery: Low")

alter table public.vehicles
  add column if not exists powertrain    text not null default '',   -- '' = petrol / diesel
  add column if not exists battery_level text,                       -- null = not checked yet
  add column if not exists battery_at    timestamptz,
  add column if not exists battery_by    uuid references public.profiles(id) on delete set null;

do $$
begin
  alter table public.vehicles add constraint vehicles_powertrain_check
    check (powertrain in ('', 'hybrid', 'phev', 'ev'));
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.vehicles add constraint vehicles_battery_level_check
    check (battery_level is null or battery_level in ('full', 'half', 'low', 'flat'));
exception when duplicate_object then null;
end $$;

-- Who / when: set by the database on every change of level, never by the phone
create or replace function public.vehicles_battery_stamp() returns trigger
language plpgsql as $$
begin
  if new.battery_level is distinct from old.battery_level then
    if new.battery_level is null then
      new.battery_at := null; new.battery_by := null;
    else
      new.battery_at := now(); new.battery_by := coalesce(auth.uid(), new.battery_by);
    end if;
  else
    new.battery_at := old.battery_at; new.battery_by := old.battery_by;
  end if;
  return new;
end $$;

drop trigger if exists vehicles_battery_stamp on public.vehicles;
create trigger vehicles_battery_stamp before update on public.vehicles
  for each row execute function public.vehicles_battery_stamp();

-- Each check → the car's work log
create or replace function public.vehicles_battery_to_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.battery_level is not null and new.battery_level is distinct from old.battery_level then
    insert into vehicle_work_log (vehicle_id, note, created_by)
    values (new.id, '🔋 Battery: ' || initcap(new.battery_level), coalesce(auth.uid(), new.battery_by));
  end if;
  return null;
end $$;

drop trigger if exists vehicles_battery_to_log on public.vehicles;
create trigger vehicles_battery_to_log after update of battery_level on public.vehicles
  for each row execute function public.vehicles_battery_to_log();

select count(*) filter (where powertrain <> '') as hybrid_or_electric, count(*) as cars from public.vehicles;
