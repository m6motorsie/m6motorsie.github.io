-- M6 Motors — mats on the shelf.
-- Run after 050_viewing_reminders.sql. Safe to run again.
--
-- The mats already bought sit on a shelf; each set is one row here. When someone
-- notes "Mats missing" on a car and a set on the shelf fits (same make, and the
-- same model or "any model"), the app says so and offers to keep that set for the
-- car — so nobody orders mats we already have. The issue then says "from the shelf".
--   • anyone on staff adds sets and takes them for a car
--   • who added / who took it and when are stamped here, not by the phone
--   • whoever added a set, or an admin, can delete it

create table if not exists public.mat_stock (
  id          bigint generated always as identity primary key,
  make        text not null default '',          -- '' = fits any car (universal)
  model       text not null default '',          -- '' = any model of that make
  description text not null default '',          -- e.g. "black carpet, front + rear"
  place       text not null default '',          -- where it is, e.g. "valet room shelf"
  added_by    uuid default auth.uid() references public.profiles(id) on delete set null,
  added_at    timestamptz not null default now(),
  used_at     timestamptz,                       -- set = taken off the shelf
  used_by     uuid references public.profiles(id) on delete set null,
  vehicle_id  uuid references public.vehicles(id) on delete set null  -- the car it went to
);

create index if not exists mat_stock_shelf_idx on public.mat_stock (used_at);

create or replace function public.mat_stock_stamp() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.added_by := coalesce(auth.uid(), new.added_by);
    new.added_at := now();
    new.used_at := null; new.used_by := null; new.vehicle_id := null;
  else
    new.added_by := old.added_by;
    new.added_at := old.added_at;
    if new.used_at is null then
      new.used_by := null; new.vehicle_id := null;   -- back on the shelf (Undo)
    elsif old.used_at is null then
      new.used_at := now(); new.used_by := auth.uid();
    else
      new.used_at := old.used_at; new.used_by := old.used_by;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists mat_stock_stamp on public.mat_stock;
create trigger mat_stock_stamp before insert or update on public.mat_stock
  for each row execute function public.mat_stock_stamp();

alter table public.mat_stock enable row level security;

drop policy if exists "staff read mats"           on public.mat_stock;
drop policy if exists "staff add mats"            on public.mat_stock;
drop policy if exists "staff use mats"            on public.mat_stock;
drop policy if exists "own or admin remove mats"  on public.mat_stock;
create policy "staff read mats" on public.mat_stock
  for select to authenticated using (public.is_staff());
create policy "staff add mats" on public.mat_stock
  for insert to authenticated with check (public.is_staff());
create policy "staff use mats" on public.mat_stock
  for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "own or admin remove mats" on public.mat_stock
  for delete to authenticated using (public.is_admin() or added_by = auth.uid());

do $$
begin
  alter publication supabase_realtime add table public.mat_stock;
exception when duplicate_object then null;
end $$;

select count(*) as mats_on_shelf from public.mat_stock where used_at is null;
