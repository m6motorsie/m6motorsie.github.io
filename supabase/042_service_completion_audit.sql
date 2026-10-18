-- M6 Motors - retain an audit trail when paid service completions are added or removed.
-- Run after 041_trade_cars.sql. Safe to run again.

create table if not exists public.service_completion_audit (
  id bigint generated always as identity primary key,
  completion_id bigint not null,
  vehicle_id uuid,
  action text not null check (action in ('completed', 'removed')),
  service text not null,
  user_id uuid,
  user_name text,
  plate text,
  vehicle text,
  completed_at timestamptz not null,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_by_name text,
  changed_at timestamptz not null default now()
);

create index if not exists service_completion_audit_changed_at_idx
  on public.service_completion_audit (changed_at desc);
create index if not exists service_completion_audit_service_changed_at_idx
  on public.service_completion_audit (service, changed_at desc);

alter table public.service_completion_audit enable row level security;
revoke all on table public.service_completion_audit from anon, authenticated;
grant select on table public.service_completion_audit to authenticated;
drop policy if exists "admin read completion audit" on public.service_completion_audit;
create policy "admin read completion audit" on public.service_completion_audit
  for select to authenticated using (public.is_admin());

create or replace function public.audit_service_completion_change() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  actor_name text;
begin
  select p.display_name into actor_name
  from public.profiles as p where p.id = actor_id;

  if tg_op = 'INSERT' then
    insert into public.service_completion_audit
      (completion_id, vehicle_id, action, service, user_id, user_name, plate, vehicle,
       completed_at, changed_by, changed_by_name)
    values (new.id, new.vehicle_id, 'completed', new.service, new.user_id, new.user_name,
            new.plate, new.vehicle, new.done_at, actor_id, actor_name);
    return new;
  end if;

  insert into public.service_completion_audit
    (completion_id, vehicle_id, action, service, user_id, user_name, plate, vehicle,
     completed_at, changed_by, changed_by_name)
  values (old.id, old.vehicle_id, 'removed', old.service, old.user_id, old.user_name,
          old.plate, old.vehicle, old.done_at, actor_id, actor_name);
  return old;
end;
$$;

drop trigger if exists service_completion_audit_log on public.service_completions;
create trigger service_completion_audit_log
  after insert or delete on public.service_completions
  for each row execute function public.audit_service_completion_change();

revoke all on function public.audit_service_completion_change() from public, anon, authenticated;
