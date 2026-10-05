-- =====================================================================
-- M6 Motors — work log: what was done on a car, by whom, when
-- Run once (after 024_vehicle_issues.sql): SQL Editor → New query → paste → Run.
-- Safe to run again.
-- =====================================================================
-- Anyone on staff can log work on a car ("Grille wrapped"); the database stamps
-- who / when. When an issue is marked Fixed it's logged automatically, and
-- taken off the log again if the fix is undone. The person who wrote an entry
-- (or an admin) can delete it.

create table if not exists public.vehicle_work_log (
  id         bigint generated always as identity primary key,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  note       text not null check (btrim(note) <> ''),
  issue_id   bigint references public.vehicle_issues(id) on delete set null,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists vehicle_work_log_vehicle_idx on public.vehicle_work_log (vehicle_id);

-- Who and when can't be faked (an entry made for a fixed issue keeps the fixer)
create or replace function public.vehicle_work_log_stamp() returns trigger
language plpgsql as $$
begin
  new.created_by := coalesce(auth.uid(), new.created_by);
  new.created_at := now();
  return new;
end $$;

drop trigger if exists vehicle_work_log_stamp on public.vehicle_work_log;
create trigger vehicle_work_log_stamp before insert on public.vehicle_work_log
  for each row execute function public.vehicle_work_log_stamp();

alter table public.vehicle_work_log enable row level security;

drop policy if exists "staff read work log"  on public.vehicle_work_log;
drop policy if exists "staff add work log"   on public.vehicle_work_log;
drop policy if exists "own or admin remove work log" on public.vehicle_work_log;
create policy "staff read work log" on public.vehicle_work_log
  for select to authenticated using (public.is_staff());
create policy "staff add work log" on public.vehicle_work_log
  for insert to authenticated with check (public.is_staff());
create policy "own or admin remove work log" on public.vehicle_work_log
  for delete to authenticated using (public.is_admin() or created_by = auth.uid());

-- An issue marked Fixed goes on the log; undoing the fix takes it off again
create or replace function public.vehicle_issues_to_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.fixed_at is not null and old.fixed_at is null then
    insert into vehicle_work_log (vehicle_id, note, issue_id, created_by)
    values (new.vehicle_id,
            'Fixed: ' || case new.kind when 'wheels' then 'Wheels / alloys'
                                       when 'interior' then 'Missing interior part'
                                       when 'scratch' then 'Scratch / paint'
                                       else 'Other' end
                      || case when btrim(new.note) <> '' then ' — ' || btrim(new.note) else '' end,
            new.id, new.fixed_by);
  elsif new.fixed_at is null and old.fixed_at is not null then
    delete from vehicle_work_log where issue_id = new.id;
  end if;
  return null;
end $$;

drop trigger if exists vehicle_issues_to_log on public.vehicle_issues;
create trigger vehicle_issues_to_log after update of fixed_at on public.vehicle_issues
  for each row execute function public.vehicle_issues_to_log();

-- Live updates between phones
do $$
begin
  alter publication supabase_realtime add table public.vehicle_work_log;
exception when duplicate_object then null;
end $$;
