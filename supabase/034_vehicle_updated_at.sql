-- =====================================================================
-- M6 Motors — remember when each car last changed
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- When someone comes back to the app it now downloads only the cars that
-- changed since last time, instead of every car again (saves data on
-- Supabase's free plan).

alter table public.vehicles
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.vehicles_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists vehicles_touch on public.vehicles;
create trigger vehicles_touch before insert or update on public.vehicles
  for each row execute function public.vehicles_touch();

create index if not exists vehicles_updated_at_idx on public.vehicles (updated_at);
