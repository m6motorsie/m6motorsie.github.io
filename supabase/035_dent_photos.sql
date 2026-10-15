-- =====================================================================
-- M6 Motors — photos of the dent (up to 3), shown on the Dent list only
-- Run once (after 031): SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================

alter table public.vehicles
  add column if not exists dent_photos text[] not null default '{}';

alter table public.vehicles drop constraint if exists vehicles_dent_photos_max;
alter table public.vehicles add constraint vehicles_dent_photos_max
  check (cardinality(dent_photos) <= 3);

-- Same as 031, plus: adding / changing dent photos needs "Can use Dent".
create or replace function public.vehicles_dent_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null then return new; end if;
  -- Taking a car off the list (Done)
  if old.dent_since is not null and new.dent_since is null then
    if not public.can_finish_dent() then
      raise exception 'Only the person who signs off dents can mark them done' using errcode = '42501';
    end if;
  -- Adding to the list or changing what's written
  elsif new.dent_notes  is distinct from old.dent_notes
     or new.dent_date   is distinct from old.dent_date
     or new.dent_since  is distinct from old.dent_since
     or new.dent_photos is distinct from old.dent_photos then
    if not public.can_dent() then
      raise exception 'You don''t have permission to use Dent' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists vehicles_dent_guard on public.vehicles;
create trigger vehicles_dent_guard before update on public.vehicles
  for each row execute function public.vehicles_dent_guard();
