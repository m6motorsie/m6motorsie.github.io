-- =====================================================================
-- M6 Motors — viewings + a quick "refresh" of the car before it
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- Then redeploy the Edge Function (swift-responder) with the new
-- supabase/functions/notify/index.ts.
-- =====================================================================
-- A manager books a viewing on a car (day + time + note). The refresh people
-- (Team screen switch; starts with Glenio and Yann) get a notification, tap
-- "Start refresh" then "Refreshed", and the manager who booked it is told at
-- each step. A car stays on the Viewings list until a manager clears it.

alter table public.vehicles
  add column if not exists viewing_at         timestamptz,                 -- day + time of the viewing
  add column if not exists viewing_note       text not null default '',
  add column if not exists viewing_by         uuid references public.profiles(id) on delete set null,  -- who booked it
  add column if not exists refresh_state      text not null default 'pending',
  add column if not exists refresh_by         uuid references public.profiles(id) on delete set null,
  add column if not exists refresh_started_at timestamptz,
  add column if not exists refresh_at         timestamptz;

alter table public.vehicles drop constraint if exists vehicles_refresh_state_check;
alter table public.vehicles add constraint vehicles_refresh_state_check
  check (refresh_state in ('pending', 'doing', 'done'));

-- Who does the refresh (set on the Team screen). Starting list: Glenio, Yann.
alter table public.profiles
  add column if not exists does_refresh boolean not null default false;

update public.profiles
set does_refresh = true
where split_part(lower(btrim(display_name)), ' ', 1) in ('glenio', 'yann');

-- Only admins may change admin rights and the permission flags.
create or replace function public.profiles_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not public.is_admin() and (
       new.is_admin     is distinct from old.is_admin
    or new.handles_sold is distinct from old.handles_sold
    or new.sold_alerts  is distinct from old.sold_alerts
    or new.can_dent     is distinct from old.can_dent
    or new.can_bodyshop is distinct from old.can_bodyshop
    or new.show_count   is distinct from old.show_count
    or new.loan_alerts  is distinct from old.loan_alerts
    or new.does_refresh is distinct from old.does_refresh) then
    raise exception 'Only admins can change this' using errcode = '42501';
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  return new;
end $$;

create or replace function public.does_refresh() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select does_refresh from profiles where id = auth.uid()), false)
$$;

-- Booking is for managers; the refresh is for the refresh people (or a manager).
-- Who / when is always set here, never by the app.
create or replace function public.vehicles_viewing_guard() returns trigger
language plpgsql as $$
begin
  if new.viewing_at is distinct from old.viewing_at or new.viewing_note is distinct from old.viewing_note then
    if auth.uid() is not null and not public.is_admin() then
      raise exception 'Only managers can book viewings' using errcode = '42501';
    end if;
    if new.viewing_at is null then                      -- viewing cleared
      new.viewing_note := '';
      new.viewing_by := null;
      new.refresh_state := 'pending';
    elsif old.viewing_at is null then                   -- new viewing: fresh refresh
      new.viewing_by := coalesce(auth.uid(), new.viewing_by);
      new.refresh_state := 'pending';
    else                                                -- time or note changed
      new.viewing_by := old.viewing_by;
    end if;
  else
    new.viewing_by := old.viewing_by;
  end if;

  if new.refresh_state is distinct from old.refresh_state then
    if auth.uid() is not null and not public.is_admin() and not public.does_refresh() then
      raise exception 'You are not set up to do refreshes' using errcode = '42501';
    end if;
    if new.refresh_state = 'doing' then
      new.refresh_by := coalesce(auth.uid(), old.refresh_by);
      new.refresh_started_at := now();
      new.refresh_at := null;
    elsif new.refresh_state = 'done' then
      new.refresh_by := coalesce(old.refresh_by, auth.uid());
      new.refresh_started_at := coalesce(old.refresh_started_at, now());
      new.refresh_at := now();
    else
      new.refresh_by := null;
      new.refresh_started_at := null;
      new.refresh_at := null;
    end if;
  else
    new.refresh_by := old.refresh_by;
    new.refresh_started_at := old.refresh_started_at;
    new.refresh_at := old.refresh_at;
  end if;
  return new;
end $$;

drop trigger if exists vehicles_viewing_guard on public.vehicles;
create trigger vehicles_viewing_guard before update on public.vehicles
  for each row execute function public.vehicles_viewing_guard();

-- Notifications (the Edge Function re-checks everything itself)
create or replace function public.notify_viewing() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.viewing_at is not null and new.viewing_at is distinct from old.viewing_at then
    perform public.call_notify(jsonb_build_object('vehicle_id', new.id, 'event', 'viewing_booked'));
  end if;
  if new.viewing_at is not null and new.refresh_state is distinct from old.refresh_state
     and new.refresh_state in ('doing', 'done') then
    perform public.call_notify(jsonb_build_object('vehicle_id', new.id,
      'event', case new.refresh_state when 'doing' then 'refresh_doing' else 'refresh_done' end));
  end if;
  return null;
end $$;

drop trigger if exists vehicles_notify_viewing on public.vehicles;
create trigger vehicles_notify_viewing after update of viewing_at, refresh_state on public.vehicles
  for each row execute function public.notify_viewing();

-- Who does refreshes now
select display_name, does_refresh from public.profiles order by display_name;
