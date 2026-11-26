-- M6 Motors — the engine type (Hybrid / Plug-in / Electric) is a car detail:
-- only admins change it, like the rest of the car form. The battery level itself
-- stays open to everyone on staff (052_*.sql).
-- Run after 052_battery.sql. Safe to run again.
-- (Replaces vehicles_details_guard from 017 with powertrain added.)

create or replace function public.vehicles_details_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not public.is_admin() and (
       new.reg_ie           is distinct from old.reg_ie
    or new.reg_imp          is distinct from old.reg_imp
    or new.make             is distinct from old.make
    or new.model            is distinct from old.model
    or new.color            is distinct from old.color
    or new.notes            is distinct from old.notes
    or new.photo_path       is distinct from old.photo_path
    or new.urgent           is distinct from old.urgent
    or new.delivery_day     is distinct from old.delivery_day
    or new.delivery_time    is distinct from old.delivery_time
    or new.delivery_date    is distinct from old.delivery_date
    or new.stock_status     is distinct from old.stock_status
    or new.seller           is distinct from old.seller
    or new.vrt_nct          is distinct from old.vrt_nct
    or new.mechanical_notes is distinct from old.mechanical_notes
    or new.estimate         is distinct from old.estimate
    or new.powertrain       is distinct from old.powertrain) then
    raise exception 'Only admins can edit a car' using errcode = '42501';
  end if;
  return new;
end $$;
