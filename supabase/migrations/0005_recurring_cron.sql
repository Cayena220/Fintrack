-- Recurring bills / income.
-- A daily pg_cron job posts every due occurrence as a normal transaction and
-- moves next_run_on forward. Missed periods (e.g. the job was paused) are
-- caught up in one run.

create extension if not exists pg_cron;

-- Next occurrence after `d`. Monthly/yearly dates are computed from the rule's
-- start date so a rule starting on Jan 31 runs Feb 28, Mar 31, Apr 30, ...
-- instead of drifting to the 28th forever.
create or replace function public.next_recurring_date(
  d date, frequency text, step integer, anchor date
)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  months_per_step integer;
  months_elapsed integer;
begin
  if frequency = 'daily' then
    return d + step;
  elsif frequency = 'weekly' then
    return d + 7 * step;
  end if;

  months_per_step := case frequency when 'monthly' then step when 'yearly' then 12 * step end;
  if months_per_step is null then
    raise exception 'Unknown frequency %', frequency;
  end if;

  months_elapsed := (extract(year from d)::int - extract(year from anchor)::int) * 12
                  + (extract(month from d)::int - extract(month from anchor)::int);

  return (anchor + make_interval(
    months => ((months_elapsed / months_per_step) + 1) * months_per_step
  ))::date;
end;
$$;

-- Posts due occurrences. p_user = null processes everyone (cron);
-- a user id restricts it to that user's rules.
create or replace function public.process_recurring_rules(p_user uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r       record;
  run_on  date;
  posted  integer := 0;
  guard   integer;
begin
  for r in
    select *
    from public.recurring_rules
    where is_active
      and next_run_on <= current_date
      and (p_user is null or user_id = p_user)
    for update skip locked
  loop
    run_on := r.next_run_on;
    guard := 0;

    while run_on <= current_date
      and (r.end_date is null or run_on <= r.end_date)
      and guard < 1000
    loop
      insert into public.transactions
        (user_id, account_id, category_id, type, amount, occurred_on, note, recurring_rule_id)
      values
        (r.user_id, r.account_id, r.category_id, r.type, r.amount, run_on, r.note, r.id);

      posted := posted + 1;
      guard := guard + 1;
      run_on := public.next_recurring_date(run_on, r.frequency, r."interval", r.start_date);
    end loop;

    update public.recurring_rules
    set next_run_on = run_on,
        is_active   = (r.end_date is null or run_on <= r.end_date)
    where id = r.id;
  end loop;

  return posted;
end;
$$;

-- Only the scheduler / service role may process everyone's rules.
revoke execute on function public.process_recurring_rules(uuid) from public, anon, authenticated;

-- Signed-in users can post their own due rules immediately (the app calls
-- this on startup and after saving a rule that starts today).
create or replace function public.process_my_recurring_rules()
returns integer
language sql
security definer
set search_path = ''
as $$
  select public.process_recurring_rules((select auth.uid()))
  where (select auth.uid()) is not null;
$$;

revoke execute on function public.process_my_recurring_rules() from public, anon;
grant execute on function public.process_my_recurring_rules() to authenticated;

-- Every day at 00:05 UTC.
select cron.schedule(
  'process-recurring-rules',
  '5 0 * * *',
  $$select public.process_recurring_rules()$$
);
