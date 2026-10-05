-- =====================================================================
-- M6 Motors — issues on a car (wheel damage, missing interior part, …)
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- Anyone on staff can note a problem on a car and mark it fixed; the database
-- stamps who / when. The person who wrote it (or an admin) can delete it.

create table if not exists public.vehicle_issues (
  id         bigint generated always as identity primary key,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  kind       text not null check (kind in ('wheels', 'interior', 'scratch', 'other')),
  note       text not null default '',
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  fixed_by   uuid references public.profiles(id) on delete set null,
  fixed_at   timestamptz
);

create index if not exists vehicle_issues_vehicle_idx on public.vehicle_issues (vehicle_id);

-- Who wrote it and who fixed it can't be faked
create or replace function public.vehicle_issues_stamp() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.created_at := now();
    new.fixed_by := null;
    new.fixed_at := null;
  else
    new.vehicle_id := old.vehicle_id;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    if new.fixed_at is not null and old.fixed_at is null then
      new.fixed_by := auth.uid();
      new.fixed_at := now();
    elsif new.fixed_at is null then
      new.fixed_by := null;
    else
      new.fixed_by := old.fixed_by;
      new.fixed_at := old.fixed_at;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists vehicle_issues_stamp on public.vehicle_issues;
create trigger vehicle_issues_stamp before insert or update on public.vehicle_issues
  for each row execute function public.vehicle_issues_stamp();

alter table public.vehicle_issues enable row level security;

drop policy if exists "staff read issues"   on public.vehicle_issues;
drop policy if exists "staff add issues"    on public.vehicle_issues;
drop policy if exists "staff update issues" on public.vehicle_issues;
drop policy if exists "own or admin remove issues" on public.vehicle_issues;
create policy "staff read issues" on public.vehicle_issues
  for select to authenticated using (public.is_staff());
create policy "staff add issues" on public.vehicle_issues
  for insert to authenticated with check (public.is_staff());
create policy "staff update issues" on public.vehicle_issues
  for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "own or admin remove issues" on public.vehicle_issues
  for delete to authenticated using (public.is_admin() or created_by = auth.uid());

-- Live updates between phones
do $$
begin
  alter publication supabase_realtime add table public.vehicle_issues;
exception when duplicate_object then null;
end $$;
