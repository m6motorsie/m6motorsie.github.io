-- =====================================================================
-- M6 Motors — mark a car as out on a test drive (no customer details)
-- Run once (after 025_work_log.sql): SQL Editor → New query → paste → Run.
-- Safe to run again.
-- =====================================================================
-- Only the people with "Test drives" on the Team screen (starts with Alan,
-- Eanna and Derek) can mark a car out / back. Who and since when are set here.
-- When the car is back, the drive goes on the car's work log by itself.

alter table public.vehicles
  add column if not exists testdrive_since timestamptz,
  add column if not exists testdrive_by    uuid references public.profiles(id) on delete set null;

alter table public.profiles
  add column if not exists can_testdrive boolean not null default false;

-- Starting list: Alan, Eanna, Derek — matched by first name. Check the Team
-- screen afterwards (e.g. if two people are called Alan).
update public.profiles
set can_testdrive = true
where split_part(lower(btrim(display_name)), ' ', 1) in ('alan', 'eanna', 'derek');

-- Only admins may change admin rights and the permission flags.
create or replace function public.profiles_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not public.is_admin() and (
       new.is_admin      is distinct from old.is_admin
    or new.handles_sold  is distinct from old.handles_sold
    or new.sold_alerts   is distinct from old.sold_alerts
    or new.can_dent      is distinct from old.can_dent
    or new.can_bodyshop  is distinct from old.can_bodyshop
    or new.show_count    is distinct from old.show_count
    or new.loan_alerts   is distinct from old.loan_alerts
    or new.does_refresh  is distinct from old.does_refresh
    or new.can_testdrive is distinct from old.can_testdrive) then
    raise exception 'Only admins can change this' using errcode = '42501';
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  return new;
end $$;

create or replace function public.can_testdrive() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select can_testdrive from profiles where id = auth.uid()), false)
$$;

create or replace function public.vehicles_testdrive_guard() returns trigger
language plpgsql as $$
begin
  if (new.testdrive_since is null) is distinct from (old.testdrive_since is null) then
    if auth.uid() is not null and not public.can_testdrive() then
      raise exception 'Only the sales team can mark test drives' using errcode = '42501';
    end if;
    if new.testdrive_since is not null then
      new.testdrive_since := now();
      new.testdrive_by := coalesce(auth.uid(), new.testdrive_by);
    else
      new.testdrive_by := null;
    end if;
  else
    new.testdrive_since := old.testdrive_since;
    new.testdrive_by := old.testdrive_by;
  end if;
  return new;
end $$;

drop trigger if exists vehicles_testdrive_guard on public.vehicles;
create trigger vehicles_testdrive_guard before update on public.vehicles
  for each row execute function public.vehicles_testdrive_guard();

-- Back from a test drive → on the car's work log ("Test drive · 35 min")
create or replace function public.vehicles_testdrive_to_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  mins int;
begin
  if old.testdrive_since is not null and new.testdrive_since is null then
    mins := greatest(1, round(extract(epoch from (now() - old.testdrive_since)) / 60)::int);
    insert into vehicle_work_log (vehicle_id, note, created_by)
    values (new.id,
            'Test drive · ' || case when mins >= 60 then (mins / 60) || ' h ' || (mins % 60) || ' min'
                                    else mins || ' min' end,
            coalesce(old.testdrive_by, auth.uid()));
  end if;
  return null;
end $$;

drop trigger if exists vehicles_testdrive_to_log on public.vehicles;
create trigger vehicles_testdrive_to_log after update of testdrive_since on public.vehicles
  for each row execute function public.vehicles_testdrive_to_log();

-- Who can mark test drives now
select display_name, can_testdrive from public.profiles order by display_name;
