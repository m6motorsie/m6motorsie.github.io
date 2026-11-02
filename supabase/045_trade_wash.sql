-- =====================================================================
-- M6 Motors — "Wash" on trade cars
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- The sales team sometimes needs a part-ex washed before it's sold on (photos
-- for the trade buyers). They tap "🧽 Wash" on the trade card; the refresh
-- people (profiles.does_refresh: Glenio, Yann) get a push and see the car on
-- their Viewings tab with Start wash → Washed, and whoever asked is told when
-- it's done. The refresh people can't read trade_cars (it has prices in it),
-- so they get only the car itself through trade_wash_list() and change only
-- the wash through trade_wash_set().
-- Needs the Edge Function events trade_wash_asked / trade_wash_done (redeploy
-- swift-responder with supabase/functions/notify/index.ts).

alter table public.trade_cars
  add column if not exists wash_state      text not null default 'none',
  add column if not exists wash_note       text not null default '',
  add column if not exists wash_asked_by   uuid references public.profiles(id) on delete set null,
  add column if not exists wash_asked_at   timestamptz,
  add column if not exists wash_by         uuid references public.profiles(id) on delete set null,
  add column if not exists wash_started_at timestamptz,
  add column if not exists wash_at         timestamptz;

alter table public.trade_cars drop constraint if exists trade_cars_wash_state_check;
alter table public.trade_cars add constraint trade_cars_wash_state_check
  check (wash_state in ('none', 'asked', 'doing', 'done'));

-- Who may do what, and who / when stamped by the database
create or replace function public.trade_cars_wash_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.wash_state := 'none';
    new.wash_asked_by := null; new.wash_asked_at := null;
    new.wash_by := null; new.wash_started_at := null; new.wash_at := null;
    return new;
  end if;
  if new.wash_state is not distinct from old.wash_state then
    new.wash_asked_by := old.wash_asked_by; new.wash_asked_at := old.wash_asked_at;
    new.wash_by := old.wash_by; new.wash_started_at := old.wash_started_at; new.wash_at := old.wash_at;
    return new;
  end if;
  -- Asking for a wash / taking the request back: the sales team (or a manager);
  -- the washer may also cancel a wash they started (doing → asked)
  if new.wash_state in ('none', 'asked') and not (old.wash_state = 'doing' and new.wash_state = 'asked') then
    if auth.uid() is not null and not public.can_trade() then
      raise exception 'Only the sales team can ask for a wash' using errcode = '42501';
    end if;
  elsif auth.uid() is not null and not public.is_admin() and not public.does_refresh() then
    raise exception 'You are not set up to do refreshes' using errcode = '42501';
  end if;
  if new.wash_state = 'asked' and old.wash_state <> 'doing' then
    new.wash_asked_by := coalesce(auth.uid(), old.wash_asked_by);
    new.wash_asked_at := now();
  else
    new.wash_asked_by := old.wash_asked_by; new.wash_asked_at := old.wash_asked_at;
  end if;
  if new.wash_state = 'doing' then
    new.wash_by := coalesce(auth.uid(), old.wash_by);
    new.wash_started_at := coalesce(case when old.wash_state = 'done' then old.wash_started_at end, now());
    new.wash_at := null;
  elsif new.wash_state = 'done' then
    new.wash_by := coalesce(old.wash_by, auth.uid());
    new.wash_started_at := coalesce(old.wash_started_at, now());
    new.wash_at := now();
  else
    new.wash_by := null; new.wash_started_at := null; new.wash_at := null;
  end if;
  if new.wash_state = 'none' then
    new.wash_asked_by := null; new.wash_asked_at := null; new.wash_note := '';
  end if;
  return new;
end $$;

drop trigger if exists trade_cars_wash_guard on public.trade_cars;
create trigger trade_cars_wash_guard before insert or update on public.trade_cars
  for each row execute function public.trade_cars_wash_guard();

-- The refresh people's list: just the car and the wash, no prices.
-- Asked / in progress, and the ones washed in the last 12 hours (for Undo).
create or replace function public.trade_wash_list()
returns table (
  id uuid, reg text, make text, model text, year text, color text, photo_path text,
  wash_state text, wash_note text, wash_asked_by uuid, wash_asked_at timestamptz,
  wash_by uuid, wash_started_at timestamptz, wash_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select t.id, t.reg, t.make, t.model, t.year, t.color, t.photo_path,
         t.wash_state, t.wash_note, t.wash_asked_by, t.wash_asked_at,
         t.wash_by, t.wash_started_at, t.wash_at
  from trade_cars t
  where (public.does_refresh() or public.can_trade())
    and t.status <> 'retail'
    and (t.wash_state in ('asked', 'doing') or (t.wash_state = 'done' and t.wash_at > now() - interval '12 hours'))
  order by t.wash_asked_at
$$;

-- Start wash (doing) / Washed (done) / Cancel (asked), for the refresh people
create or replace function public.trade_wash_set(p_id uuid, p_state text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_admin() or public.does_refresh()) then
    raise exception 'You are not set up to do refreshes' using errcode = '42501';
  end if;
  if p_state not in ('asked', 'doing', 'done') then
    raise exception 'Not a wash step' using errcode = '22023';
  end if;
  update trade_cars set wash_state = p_state
  where id = p_id and wash_state <> 'none'
    and (p_state <> 'asked' or wash_state = 'doing');
end $$;

revoke all on function public.trade_wash_list() from public, anon;
revoke all on function public.trade_wash_set(uuid, text) from public, anon;
grant execute on function public.trade_wash_list() to authenticated;
grant execute on function public.trade_wash_set(uuid, text) to authenticated;

-- Pushes: asked → the refresh people; washed → whoever asked
create or replace function public.notify_trade_wash() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.wash_state is distinct from old.wash_state and new.wash_state in ('asked', 'done')
     and not (old.wash_state = 'doing' and new.wash_state = 'asked') then
    perform public.call_notify(jsonb_build_object('trade_id', new.id,
      'event', case new.wash_state when 'asked' then 'trade_wash_asked' else 'trade_wash_done' end));
  end if;
  return null;
exception when others then
  raise warning 'notify_trade_wash failed: %', sqlerrm;
  return null;
end $$;

drop trigger if exists trade_cars_notify_wash on public.trade_cars;
create trigger trade_cars_notify_wash after update on public.trade_cars
  for each row execute function public.notify_trade_wash();
