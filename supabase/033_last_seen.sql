-- =====================================================================
-- M6 Motors — "last seen" for each person (shown on the Team screen)
-- Run once: SQL Editor → New query → paste → Run. Safe to run again.
-- =====================================================================
-- The app calls touch_last_seen() when it opens and every few minutes while
-- it's on screen. Each person can only stamp their own time.

alter table public.profiles
  add column if not exists last_seen_at timestamptz;

create or replace function public.touch_last_seen() returns void
language sql security definer set search_path = public as $$
  update profiles set last_seen_at = now() where id = auth.uid();
$$;

revoke all on function public.touch_last_seen() from public;
grant execute on function public.touch_last_seen() to authenticated;
