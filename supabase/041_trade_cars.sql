-- =====================================================================
-- M6 Motors — Trade cars: part-exchanges sold on to the trade
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- A customer's part-ex that M6 doesn't keep for retail is sold on to other
-- dealers / garages / auctions. Each trade car: what it is, the deal it came
-- in on, what the customer was given (allowance), its papers, the offers from
-- buyers, and its journey: on site → sold → collected → paid.
-- Only managers and the sales team (Sales switch on the Team screen) can see
-- or change it: it has prices in it. Only managers can delete.

create table if not exists public.trade_cars (
  id            uuid primary key default gen_random_uuid(),
  reg           text not null default '',
  make          text not null default '',
  model         text not null default '',
  year          text not null default '',
  mileage       text not null default '',
  color         text not null default '',
  part_ex_for   uuid references public.vehicles(id) on delete set null,
  part_ex_label text not null default '',          -- the car it was traded against (kept if that car goes)
  allowance     numeric(10, 2),                    -- what the customer was given for it
  status        text not null default 'in' check (status in ('in', 'sold', 'collected', 'retail')),
  buyer         text not null default '',
  sold_price    numeric(10, 2),
  collect_date  date,
  sold_at       timestamptz,
  collected_at  timestamptz,
  paid_at       timestamptz,
  has_v5        boolean not null default false,
  has_two_keys  boolean not null default false,
  has_history   boolean not null default false,
  notes         text not null default '',
  photo_path    text,
  created_by    uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.trade_offers (
  id         bigint generated always as identity primary key,
  trade_id   uuid not null references public.trade_cars(id) on delete cascade,
  buyer      text not null check (btrim(buyer) <> ''),
  amount     numeric(10, 2) not null check (amount >= 0),
  note       text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists trade_offers_trade_idx on public.trade_offers (trade_id);

-- Managers + the sales team
create or replace function public.can_trade() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or public.can_testdrive()
$$;

-- Who / when are stamped by the database
create or replace function public.trade_cars_stamp() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.created_at := now();
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    if new.status = 'sold' and old.status is distinct from 'sold' then new.sold_at := now(); end if;
    if new.status = 'in' then new.sold_at := null; end if;
    if new.status = 'collected' and old.status is distinct from 'collected' then new.collected_at := now(); end if;
    if new.status <> 'collected' then new.collected_at := null; end if;
    if new.paid_at is not null and old.paid_at is null then new.paid_at := now(); end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trade_cars_stamp on public.trade_cars;
create trigger trade_cars_stamp before insert or update on public.trade_cars
  for each row execute function public.trade_cars_stamp();

create or replace function public.trade_offers_stamp() returns trigger
language plpgsql as $$
begin
  new.created_by := coalesce(auth.uid(), new.created_by);
  new.created_at := now();
  return new;
end $$;

drop trigger if exists trade_offers_stamp on public.trade_offers;
create trigger trade_offers_stamp before insert on public.trade_offers
  for each row execute function public.trade_offers_stamp();

alter table public.trade_cars enable row level security;
alter table public.trade_offers enable row level security;

drop policy if exists "trade read"   on public.trade_cars;
drop policy if exists "trade add"    on public.trade_cars;
drop policy if exists "trade change" on public.trade_cars;
drop policy if exists "trade remove" on public.trade_cars;
create policy "trade read"   on public.trade_cars for select to authenticated using (public.can_trade());
create policy "trade add"    on public.trade_cars for insert to authenticated with check (public.can_trade());
create policy "trade change" on public.trade_cars for update to authenticated using (public.can_trade()) with check (public.can_trade());
create policy "trade remove" on public.trade_cars for delete to authenticated using (public.is_admin());

drop policy if exists "offers read"   on public.trade_offers;
drop policy if exists "offers add"    on public.trade_offers;
drop policy if exists "offers remove" on public.trade_offers;
create policy "offers read"   on public.trade_offers for select to authenticated using (public.can_trade());
create policy "offers add"    on public.trade_offers for insert to authenticated with check (public.can_trade());
create policy "offers remove" on public.trade_offers for delete to authenticated
  using (public.is_admin() or (public.can_trade() and created_by = auth.uid()));

-- Live updates between phones
do $$
begin
  alter publication supabase_realtime add table public.trade_cars;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.trade_offers;
exception when duplicate_object then null;
end $$;
