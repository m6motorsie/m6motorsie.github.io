-- M6 Motors — history for the Overview (month by month, kept for good).
-- Run after 048_supply_alerts.sql. Safe to run again.
--
-- Cars get deleted (the Delete button, the Delivered tab's 30-day clean-up),
-- and their viewings go with them, so counting months from the cars that are
-- still there makes old months shrink. This table keeps one line per sale,
-- delivery and viewing — with the car's name, plates and salesperson copied in —
-- and is never cleaned up with the cars. The database fills it by itself:
--   • sold      : sold_at was set     (taken back off if the car goes back to Stock)
--   • delivered : delivered_at was set (taken back off on Undo / Reopen)
--   • viewing   : a viewing came off the car (done, cleared or cancelled), like the work log line
-- Only admins can read it (the Overview); nobody can change it from the app.

create table if not exists public.history_events (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('sold', 'delivered', 'viewing')),
  vehicle_id  uuid,                -- no foreign key: the line stays when the car is deleted
  at          timestamptz not null,
  make        text not null default '',
  model       text not null default '',
  reg_ie      text not null default '',
  reg_imp     text not null default '',
  seller      text not null default '',
  by_id       uuid references public.profiles(id) on delete set null,
  note        text not null default '',
  created_at  timestamptz not null default now()
);

create index if not exists history_events_at_idx on public.history_events (kind, at);
create unique index if not exists history_events_once on public.history_events (kind, vehicle_id, at);

alter table public.history_events enable row level security;
drop policy if exists "admins read history" on public.history_events;
create policy "admins read history" on public.history_events for select using (public.is_admin());

create or replace function public.vehicles_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Sale
  if tg_op = 'UPDATE' and old.sold_at is not null and old.sold_at is distinct from new.sold_at then
    delete from history_events where kind = 'sold' and vehicle_id = old.id and at = old.sold_at;
  end if;
  if new.sold_at is not null and (tg_op = 'INSERT' or old.sold_at is distinct from new.sold_at) then
    insert into history_events (kind, vehicle_id, at, make, model, reg_ie, reg_imp, seller, by_id)
    values ('sold', new.id, new.sold_at, coalesce(new.make, ''), coalesce(new.model, ''),
            coalesce(new.reg_ie, ''), coalesce(new.reg_imp, ''), btrim(coalesce(new.seller, '')), auth.uid())
    on conflict do nothing;
  elsif new.sold_at is not null and (old.seller, old.make, old.model, old.reg_ie, old.reg_imp)
        is distinct from (new.seller, new.make, new.model, new.reg_ie, new.reg_imp) then
    -- Salesperson or car corrected after the sale
    update history_events set seller = btrim(coalesce(new.seller, '')), make = coalesce(new.make, ''),
      model = coalesce(new.model, ''), reg_ie = coalesce(new.reg_ie, ''), reg_imp = coalesce(new.reg_imp, '')
    where kind in ('sold', 'delivered') and vehicle_id = new.id
      and at >= new.sold_at;
  end if;

  -- Delivery
  if tg_op = 'UPDATE' and old.delivered_at is not null and old.delivered_at is distinct from new.delivered_at then
    delete from history_events where kind = 'delivered' and vehicle_id = old.id and at = old.delivered_at;
  end if;
  if new.delivered_at is not null and (tg_op = 'INSERT' or old.delivered_at is distinct from new.delivered_at) then
    insert into history_events (kind, vehicle_id, at, make, model, reg_ie, reg_imp, seller, by_id)
    values ('delivered', new.id, new.delivered_at, coalesce(new.make, ''), coalesce(new.model, ''),
            coalesce(new.reg_ie, ''), coalesce(new.reg_imp, ''), btrim(coalesce(new.seller, '')), auth.uid())
    on conflict do nothing;
  end if;

  -- Viewing taken off the car (same moment the work log line is written, 039)
  if tg_op = 'UPDATE' and old.viewing_at is not null and new.viewing_at is null then
    insert into history_events (kind, vehicle_id, at, make, model, reg_ie, reg_imp, seller, by_id, note)
    values ('viewing', new.id, old.viewing_at, coalesce(new.make, ''), coalesce(new.model, ''),
            coalesce(new.reg_ie, ''), coalesce(new.reg_imp, ''), '', old.viewing_by,
            concat_ws(' · ',
              'booked by ' || (select display_name from profiles where id = old.viewing_by),
              case when old.refresh_state = 'done'
                   then coalesce('refreshed by ' || (select display_name from profiles where id = old.refresh_by), 'refreshed') end,
              nullif(btrim(coalesce(old.viewing_note, '')), '')))
    on conflict do nothing;
  end if;
  return null;
exception when others then
  raise warning 'vehicles_history failed: %', sqlerrm;  -- never block the car change itself
  return null;
end $$;

drop trigger if exists vehicles_history on public.vehicles;
create trigger vehicles_history after insert or update on public.vehicles
  for each row execute function public.vehicles_history();

-- ---------- First run: what's still in the database ----------
insert into public.history_events (kind, vehicle_id, at, make, model, reg_ie, reg_imp, seller)
select 'sold', id, sold_at, coalesce(make, ''), coalesce(model, ''), coalesce(reg_ie, ''), coalesce(reg_imp, ''), btrim(coalesce(seller, ''))
from public.vehicles where sold_at is not null
on conflict do nothing;

insert into public.history_events (kind, vehicle_id, at, make, model, reg_ie, reg_imp, seller)
select 'delivered', id, delivered_at, coalesce(make, ''), coalesce(model, ''), coalesce(reg_ie, ''), coalesce(reg_imp, ''), btrim(coalesce(seller, ''))
from public.vehicles where delivered_at is not null and status = 'delivered'
on conflict do nothing;

-- Viewings already done: from the work log lines (time = when the line was written)
insert into public.history_events (kind, vehicle_id, at, make, model, reg_ie, reg_imp, by_id, note)
select 'viewing', w.vehicle_id, w.created_at, coalesce(v.make, ''), coalesce(v.model, ''),
       coalesce(v.reg_ie, ''), coalesce(v.reg_imp, ''), w.created_by,
       regexp_replace(w.note, '^👀 Viewing · [^·]*· ?', '')
from public.vehicle_work_log w
left join public.vehicles v on v.id = w.vehicle_id
where w.note like '👀 Viewing%'
on conflict do nothing;

-- What's in it now, per month
select to_char(date_trunc('month', at at time zone 'Europe/Dublin'), 'YYYY-MM') as month, kind, count(*)
from public.history_events group by 1, 2 order by 1, 2;
