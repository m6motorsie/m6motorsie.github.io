-- =====================================================================
-- M6 Motors — Refresh list for cars in the yard
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- Walking the yard, the refresh people (profiles.does_refresh: Glenio, Yann)
-- or the sales team (can_testdrive) put cars that need a quick refresh on a
-- list (yard_state 'asked', with an optional note). The refresh people tap
-- Start refresh (doing) → Refreshed (done); "Refreshed" goes on the car's
-- work log. Who / when are stamped by the database.

alter table public.vehicles
  add column if not exists yard_state      text not null default 'none',
  add column if not exists yard_note       text not null default '',
  add column if not exists yard_asked_by   uuid references public.profiles(id) on delete set null,
  add column if not exists yard_asked_at   timestamptz,
  add column if not exists yard_by         uuid references public.profiles(id) on delete set null,
  add column if not exists yard_started_at timestamptz,
  add column if not exists yard_at         timestamptz;

alter table public.vehicles drop constraint if exists vehicles_yard_state_check;
alter table public.vehicles add constraint vehicles_yard_state_check
  check (yard_state in ('none', 'asked', 'doing', 'done'));

create or replace function public.vehicles_yard_guard() returns trigger
language plpgsql as $$
begin
  if new.yard_state is not distinct from old.yard_state then
    if new.yard_note is distinct from old.yard_note and auth.uid() is not null
       and not (public.is_admin() or public.does_refresh() or public.can_testdrive()) then
      raise exception 'Only the sales and refresh teams can use the refresh list' using errcode = '42501';
    end if;
    new.yard_asked_by := old.yard_asked_by; new.yard_asked_at := old.yard_asked_at;
    new.yard_by := old.yard_by; new.yard_started_at := old.yard_started_at; new.yard_at := old.yard_at;
    return new;
  end if;
  -- Putting a car on the list / taking it off: sales + refresh people + managers.
  -- Start / Refreshed / Cancel / Undo: the refresh people (or a manager).
  if new.yard_state in ('none', 'asked') and not (old.yard_state = 'doing' and new.yard_state = 'asked') then
    if auth.uid() is not null and not (public.is_admin() or public.does_refresh() or public.can_testdrive()) then
      raise exception 'Only the sales and refresh teams can use the refresh list' using errcode = '42501';
    end if;
  elsif auth.uid() is not null and not public.is_admin() and not public.does_refresh() then
    raise exception 'You are not set up to do refreshes' using errcode = '42501';
  end if;
  if new.yard_state = 'asked' and old.yard_state <> 'doing' then
    new.yard_asked_by := coalesce(auth.uid(), old.yard_asked_by);
    new.yard_asked_at := now();
  else
    new.yard_asked_by := old.yard_asked_by; new.yard_asked_at := old.yard_asked_at;
  end if;
  if new.yard_state = 'doing' then
    new.yard_by := coalesce(auth.uid(), old.yard_by);
    new.yard_started_at := coalesce(case when old.yard_state = 'done' then old.yard_started_at end, now());
    new.yard_at := null;
  elsif new.yard_state = 'done' then
    new.yard_by := coalesce(old.yard_by, auth.uid());
    new.yard_started_at := coalesce(old.yard_started_at, now());
    new.yard_at := now();
  else
    new.yard_by := null; new.yard_started_at := null; new.yard_at := null;
  end if;
  if new.yard_state = 'none' then
    new.yard_asked_by := null; new.yard_asked_at := null; new.yard_note := '';
  end if;
  return new;
end $$;

drop trigger if exists vehicles_yard_guard on public.vehicles;
create trigger vehicles_yard_guard before update on public.vehicles
  for each row execute function public.vehicles_yard_guard();

-- "Refreshed" on the car's work log
create or replace function public.vehicles_yard_to_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.yard_state = 'done' and old.yard_state is distinct from 'done' then
    insert into vehicle_work_log (vehicle_id, note, created_by)
    values (new.id, '🧽 Refreshed' || case when btrim(new.yard_note) <> '' then ' · ' || new.yard_note else '' end,
            coalesce(new.yard_by, auth.uid()));
  end if;
  return null;
end $$;

drop trigger if exists vehicles_yard_to_log on public.vehicles;
create trigger vehicles_yard_to_log after update of yard_state on public.vehicles
  for each row execute function public.vehicles_yard_to_log();
