-- =====================================================================
-- M6 Motors — viewings are booked by the sales team (Alan, Eanna, Derek)
-- Run once (after 027 and 028): SQL Editor → New query → paste → Run.
-- Safe to run again.
-- =====================================================================
-- Booking / changing / clearing a viewing now needs the sales-team switch
-- ("Sales: test drives & viewings" on the Team screen, profiles.can_testdrive)
-- instead of admin. The refresh part is unchanged.

create or replace function public.vehicles_viewing_guard() returns trigger
language plpgsql as $$
begin
  if new.viewing_at is distinct from old.viewing_at or new.viewing_note is distinct from old.viewing_note then
    if auth.uid() is not null and not public.can_testdrive() then
      raise exception 'Only the sales team can book viewings' using errcode = '42501';
    end if;
    if new.viewing_at is null then                      -- viewing cleared
      new.viewing_note := '';
      new.viewing_by := null;
      new.refresh_state := 'pending';
    elsif old.viewing_at is null then                   -- new viewing: fresh refresh
      new.viewing_by := coalesce(auth.uid(), new.viewing_by);
      new.refresh_state := 'pending';
    else                                                -- time or note changed
      new.viewing_by := old.viewing_by;
    end if;
  else
    new.viewing_by := old.viewing_by;
  end if;

  if new.refresh_state is distinct from old.refresh_state then
    if auth.uid() is not null and not public.is_admin() and not public.does_refresh() then
      raise exception 'You are not set up to do refreshes' using errcode = '42501';
    end if;
    if new.refresh_state = 'doing' then
      new.refresh_by := coalesce(auth.uid(), old.refresh_by);
      new.refresh_started_at := now();
      new.refresh_at := null;
    elsif new.refresh_state = 'done' then
      new.refresh_by := coalesce(old.refresh_by, auth.uid());
      new.refresh_started_at := coalesce(old.refresh_started_at, now());
      new.refresh_at := now();
    else
      new.refresh_by := null;
      new.refresh_started_at := null;
      new.refresh_at := null;
    end if;
  else
    new.refresh_by := old.refresh_by;
    new.refresh_started_at := old.refresh_started_at;
    new.refresh_at := old.refresh_at;
  end if;
  return new;
end $$;
