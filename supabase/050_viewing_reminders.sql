-- M6 Motors — viewing reminders.
-- Run after 049_history.sql. Safe to run again.
-- Then redeploy the Edge Function (swift-responder) with supabase/functions/notify/index.ts.
--
--   • An hour before a viewing: the refresh people and whoever booked it get
--     "⏰ Viewing at 16:00 (in 55 min)" — once per viewing, and not when it was
--     booked only minutes ago (the booking push already said it).
--   • 8am on the day: "👀 Today: 2 viewings" (also for viewings booked days ago),
--     sent with the 8am run that already exists (m6-morning-sold).
-- Cron runs in UTC: every 10 minutes from 06:00 to 19:50 UTC covers the working
-- day in Dublin in summer and winter. Each run is one quick check.

create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule('m6-viewings-soon');
exception when others then null;
end $$;

select cron.schedule('m6-viewings-soon', '*/10 6-19 * * *',
  $$select public.call_notify('{"event": "viewings_soon"}'::jsonb)$$);

select jobname, schedule, active from cron.job where jobname like 'm6-%' order by jobname;
