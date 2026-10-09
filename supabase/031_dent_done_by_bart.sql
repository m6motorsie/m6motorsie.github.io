-- =====================================================================
-- M6 Motors — only chosen people (Bart) can mark a dent Done
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- People with "Can use Dent" still add cars to the Dent list and edit what's
-- written; taking a car OFF the list (Done) needs the new "Dent done" switch.

alter table public.profiles
  add column if not exists can_finish_dent boolean not null default false;

update public.profiles
set can_finish_dent = true
where split_part(lower(btrim(display_name)), ' ', 1) = 'bart';

create or replace function public.can_finish_dent() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select can_finish_dent from profiles where id = auth.uid()), false)
$$;

-- Same as 029, plus the new switch.
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
    or new.can_testdrive is distinct from old.can_testdrive
    or new.can_finish_dent is distinct from old.can_finish_dent) then
    raise exception 'Only admins can change this' using errcode = '42501';
  end if;
  if auth.uid() is not null and not public.is_system_admin()
     and new.system_admin is distinct from old.system_admin then
    raise exception 'Only the system admin can change this' using errcode = '42501';
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  return new;
end $$;

create or replace function public.vehicles_dent_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null then return new; end if;
  -- Taking a car off the list (Done)
  if old.dent_since is not null and new.dent_since is null then
    if not public.can_finish_dent() then
      raise exception 'Only the person who signs off dents can mark them done' using errcode = '42501';
    end if;
  -- Adding to the list or changing what's written
  elsif new.dent_notes is distinct from old.dent_notes
     or new.dent_date  is distinct from old.dent_date
     or new.dent_since is distinct from old.dent_since then
    if not public.can_dent() then
      raise exception 'You don''t have permission to use Dent' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists vehicles_dent_guard on public.vehicles;
create trigger vehicles_dent_guard before update on public.vehicles
  for each row execute function public.vehicles_dent_guard();

-- Who can mark dents done now (should be Bart)
select display_name, can_dent, can_finish_dent from public.profiles order by display_name;
