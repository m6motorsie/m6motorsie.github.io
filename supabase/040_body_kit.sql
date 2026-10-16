-- =====================================================================
-- M6 Motors — Body kit: a job the managers ask for on a car
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- Works like the other jobs (Start → Done, who / when, locked to whoever
-- started it), for the person with "Body kit" ticked on the Team screen
-- (Dmytro). A manager ticks it on the car and writes which kit
-- (bodykit_note, managers only).

alter table public.vehicles
  add column if not exists bodykit_state   text not null default 'pending',
  add column if not exists bodykit_by      uuid references public.profiles(id) on delete set null,
  add column if not exists bodykit_done_at timestamptz,
  add column if not exists bodykit_note    text not null default '';

alter table public.vehicles drop constraint if exists vehicles_bodykit_state_check;
alter table public.vehicles add constraint vehicles_bodykit_state_check
  check (bodykit_state in ('pending', 'doing', 'done'));

-- The job keys (used by the job checks and the completions log)
create or replace function public.service_keys() returns text[]
language sql immutable as $$
  select array['first', 'full', 'polish', 'decrome', 'windscreen', 'repair', 'bodykit']
$$;

alter table public.vehicles drop constraint if exists vehicles_services_check;
alter table public.vehicles add constraint vehicles_services_check
  check (services <@ array['first', 'full', 'polish', 'decrome', 'windscreen', 'repair', 'bodykit']);

alter table public.profiles drop constraint if exists profiles_services_check;
alter table public.profiles add constraint profiles_services_check
  check (services <@ array['first', 'full', 'polish', 'decrome', 'windscreen', 'repair', 'bodykit']);

-- Which kit: written by the managers only
create or replace function public.vehicles_bodykit_note_guard() returns trigger
language plpgsql as $$
begin
  if new.bodykit_note is distinct from old.bodykit_note
     and auth.uid() is not null and not public.is_admin() then
    raise exception 'Only managers can change the body kit details' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists vehicles_bodykit_note_guard on public.vehicles;
create trigger vehicles_bodykit_note_guard before update on public.vehicles
  for each row execute function public.vehicles_bodykit_note_guard();
