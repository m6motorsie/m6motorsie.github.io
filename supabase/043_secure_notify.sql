-- M6 Motors - authenticate database-triggered calls to the notification function.
-- Run after 042_service_completion_audit.sql. Safe to run again.
-- Before notifications will send, add the same random secret to:
--   1) Supabase Dashboard > Vault, name: m6_notify_secret
--   2) Edge Function secrets, name: M6_NOTIFY_SECRET

create extension if not exists supabase_vault with schema vault;
create extension if not exists pg_net;

-- The shared secret stays out of this repository and is read from Vault only
-- by this privileged database function. The public anon key is not a secret.
create or replace function public.call_notify(payload jsonb) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  notify_secret text;
begin
  select s.decrypted_secret into notify_secret
  from vault.decrypted_secrets as s
  where s.name = 'm6_notify_secret'
  order by s.created_at desc
  limit 1;

  if coalesce(notify_secret, '') = '' then
    raise warning 'Notification secret m6_notify_secret is not configured';
    return;
  end if;

  perform net.http_post(
    url := 'https://tmqyymrnvcmyzjhfxeqo.supabase.co/functions/v1/swift-responder',
    body := payload,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRtcXl5bXJudmNteXpqaGZ4ZXFvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA0MjUyMDYsImV4cCI6MjEwNjAwMTIwNn0.0ZT9U60jhhAkSeLTsiyo1WyPswpEi1nfnqy_bvQxhiU',
      'x-m6-notify-secret', notify_secret
    )
  );
exception when others then
  raise warning 'call_notify failed: %', sqlerrm;
end;
$$;

-- This function can invoke the privileged notification endpoint. Only database
-- owners/trusted SECURITY DEFINER trigger functions may call it.
revoke all on function public.call_notify(jsonb) from public, anon, authenticated;
alter function public.notify_ready() set search_path = '';
alter function public.notify_loan_return() set search_path = '';
alter function public.notify_viewing() set search_path = '';

-- Route the original new-stock trigger through the same authenticated caller.
create or replace function public.notify_new_stock() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'stock' then
    perform public.call_notify(jsonb_build_object('vehicle_id', new.id, 'event', 'new_stock'));
  end if;
  return null;
exception when others then
  raise warning 'notify_new_stock failed: %', sqlerrm;
  return null;
end;
$$;
