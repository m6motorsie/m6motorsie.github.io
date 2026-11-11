-- M6 Motors — notifications for the Supplies list.
-- Run after 047_back_to_stock_resets_prep.sql. Safe to run again.
--   • profiles.supply_alerts (Team screen, "🛒 Supplies alerts" — Bart):
--     a push when someone asks for something, and at 8am what's still to buy.
--   • The sales team (profiles.can_testdrive) also gets the push when someone asks.
-- Then redeploy the Edge Function (swift-responder) with supabase/functions/notify/index.ts.

alter table public.profiles add column if not exists supply_alerts boolean not null default false;

create or replace function public.notify_supply() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.call_notify(jsonb_build_object('supply_id', new.id, 'event', 'supply_added'));
  return null;
exception when others then
  raise warning 'notify_supply failed: %', sqlerrm;
  return null;
end $$;

drop trigger if exists supplies_notify on public.supplies;
create trigger supplies_notify after insert on public.supplies
  for each row execute function public.notify_supply();

-- ---------- Profiles: only admins change jobs / switches (044 + supply_alerts) ----------
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
    or new.pay_full        is distinct from old.pay_full
    or new.supply_alerts   is distinct from old.supply_alerts) then
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

-- Bart gets the supplies alerts (turn others on from the Team screen)
update public.profiles set supply_alerts = true
where display_name ilike 'bart%'
  and not exists (select 1 from public.profiles where supply_alerts);

select display_name, supply_alerts, can_testdrive from public.profiles
where supply_alerts or can_testdrive order by display_name;
