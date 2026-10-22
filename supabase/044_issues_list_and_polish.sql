-- =====================================================================
-- M6 Motors — Issues list (mats!) + alerts, and the Polish list for Lucas
-- Run once (after 043): SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- Issues
--   • New kind "mats" (Mats missing) — the most common one.
--   • profiles.issue_alerts: a push when someone notes an issue (Bart), and
--     the open issues in the 8am summary.
-- Polish
--   • vehicles.polish_note: what to polish (managers write it when they ask).
--   • Lucas can SUGGEST a polish (polish_suggested_at / _by / _suggest_note);
--     the sales team approves it (adds Polish to the car) or says no.
--   • Pushes: polish asked for → the polish team; polish suggested → sales.
-- Pay
--   • profiles.pay_full: who is paid per Full Valet. The pay report lists only
--     them, so Lucas can do a Full Valet without it counting for pay.

-- ---------- Issues ----------
alter table public.vehicle_issues drop constraint if exists vehicle_issues_kind_check;
alter table public.vehicle_issues add constraint vehicle_issues_kind_check
  check (kind in ('mats', 'wheels', 'interior', 'scratch', 'other'));

alter table public.profiles add column if not exists issue_alerts boolean not null default false;

create or replace function public.notify_issue() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.call_notify(jsonb_build_object('vehicle_id', new.vehicle_id, 'issue_id', new.id, 'event', 'issue_added'));
  return null;
exception when others then
  raise warning 'notify_issue failed: %', sqlerrm;
  return null;
end $$;

drop trigger if exists vehicle_issues_notify on public.vehicle_issues;
create trigger vehicle_issues_notify after insert on public.vehicle_issues
  for each row execute function public.notify_issue();

-- ---------- Polish ----------
alter table public.vehicles
  add column if not exists polish_note         text not null default '',
  add column if not exists polish_suggested_at timestamptz,
  add column if not exists polish_suggested_by uuid references public.profiles(id) on delete set null,
  add column if not exists polish_suggest_note text not null default '';

-- What to polish: managers. A suggestion: the polish team (or managers). Who / when stamped here.
create or replace function public.vehicles_polish_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.polish_note is distinct from old.polish_note then
      raise exception 'Only managers can change what to polish' using errcode = '42501';
    end if;
    if (new.polish_suggested_at is null) is distinct from (old.polish_suggested_at is null)
       or new.polish_suggest_note is distinct from old.polish_suggest_note then
      if not exists (select 1 from public.profiles p where p.id = auth.uid() and 'polish' = any(p.services)) then
        raise exception 'Only the polish team can suggest a polish' using errcode = '42501';
      end if;
    end if;
  end if;
  if new.polish_suggested_at is not null and old.polish_suggested_at is null then
    new.polish_suggested_at := now();
    new.polish_suggested_by := coalesce(auth.uid(), new.polish_suggested_by);
  elsif new.polish_suggested_at is null then
    new.polish_suggested_by := null;
    new.polish_suggest_note := '';
  else
    new.polish_suggested_at := old.polish_suggested_at;
    new.polish_suggested_by := old.polish_suggested_by;
  end if;
  -- Polish added to the car: the suggestion has its answer
  if 'polish' = any(new.services) and not ('polish' = any(old.services)) then
    new.polish_suggested_at := null;
    new.polish_suggested_by := null;
    new.polish_suggest_note := '';
  end if;
  return new;
end $$;

drop trigger if exists vehicles_polish_guard on public.vehicles;
create trigger vehicles_polish_guard before update on public.vehicles
  for each row execute function public.vehicles_polish_guard();

create or replace function public.notify_polish() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if 'polish' = any(new.services) and new.status <> 'delivered'
     and (tg_op = 'INSERT' or not ('polish' = any(old.services))) then
    perform public.call_notify(jsonb_build_object('vehicle_id', new.id, 'event', 'polish_requested'));
  end if;
  if tg_op = 'UPDATE' and new.polish_suggested_at is not null and old.polish_suggested_at is null then
    perform public.call_notify(jsonb_build_object('vehicle_id', new.id, 'event', 'polish_suggested'));
  end if;
  return null;
exception when others then
  raise warning 'notify_polish failed: %', sqlerrm;
  return null;
end $$;

drop trigger if exists vehicles_notify_polish on public.vehicles;
create trigger vehicles_notify_polish after insert or update of services, polish_suggested_at on public.vehicles
  for each row execute function public.notify_polish();

-- ---------- Pay ----------
alter table public.profiles add column if not exists pay_full boolean not null default false;
-- First run only: whoever does Full Valet today is paid for it (Marcelo, Rimmas)
update public.profiles set pay_full = true
where 'full' = any(services)
  and not exists (select 1 from public.profiles where pay_full);

-- ---------- Profiles: only admins change jobs / switches ----------
create or replace function public.profiles_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not public.is_admin() and (
       new.is_admin        is distinct from old.is_admin
    or new.services        is distinct from old.services
    or new.handles_sold    is distinct from old.handles_sold
    or new.sold_alerts     is distinct from old.sold_alerts
    or new.can_dent        is distinct from old.can_dent
    or new.can_bodyshop    is distinct from old.can_bodyshop
    or new.show_count      is distinct from old.show_count
    or new.loan_alerts     is distinct from old.loan_alerts
    or new.does_refresh    is distinct from old.does_refresh
    or new.can_testdrive   is distinct from old.can_testdrive
    or new.can_finish_dent is distinct from old.can_finish_dent
    or new.issue_alerts    is distinct from old.issue_alerts
    or new.pay_full        is distinct from old.pay_full) then
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

-- Who is paid per Full Valet now
select display_name, services, pay_full from public.profiles order by display_name;
