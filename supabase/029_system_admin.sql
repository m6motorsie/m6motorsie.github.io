-- =====================================================================
-- M6 Motors — "System admin": the person who sets up the team
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- Only the system admin sees the Team screen (new people, jobs, permissions,
-- notifications). Starts with Glenio. Only a system admin can give or remove
-- this flag; other admin rights are unchanged.

alter table public.profiles
  add column if not exists system_admin boolean not null default false;

update public.profiles
set system_admin = true
where split_part(lower(btrim(display_name)), ' ', 1) = 'glenio';

create or replace function public.is_system_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select system_admin from profiles where id = auth.uid()), false)
$$;

-- Admins may change admin rights and the permission flags; only a system
-- admin may change who is a system admin.
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
  if auth.uid() is not null and not public.is_system_admin()
     and new.system_admin is distinct from old.system_admin then
    raise exception 'Only the system admin can change this' using errcode = '42501';
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  return new;
end $$;

-- Who is system admin now (should be just Glenio)
select display_name, is_admin, system_admin from public.profiles order by display_name;
