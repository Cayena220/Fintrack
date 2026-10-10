-- Run with:  npx supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

-- ---------------------------------------------------------------------------
-- Two test users. The signup trigger seeds their profile, categories and Cash.
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'alice@test.dev', '{"full_name":"Alice"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'bob@test.dev', '{}');

select is(
  (select display_name from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  'Alice', 'signup trigger creates the profile with the display name');

select is(
  (select count(*)::int from public.categories where user_id = '11111111-1111-1111-1111-111111111111'),
  14, 'signup trigger seeds 14 default categories');

select is(
  (select count(*)::int from public.accounts where user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'signup trigger creates a Cash account');

-- ---------------------------------------------------------------------------
-- Act as Alice
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

insert into public.accounts (id, name, type, initial_balance)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Bank', 'bank', 1000);

insert into public.transactions (account_id, category_id, type, amount)
select 'aaaaaaaa-0000-0000-0000-000000000001', id, 'income', 500
from public.categories where name = 'Salary';

insert into public.transactions (account_id, category_id, type, amount)
select 'aaaaaaaa-0000-0000-0000-000000000001', id, 'expense', 200
from public.categories where name = 'Groceries';

insert into public.transactions (account_id, to_account_id, type, amount)
select 'aaaaaaaa-0000-0000-0000-000000000001', id, 'transfer', 100
from public.accounts where name = 'Cash';

select is(
  (select count(*)::int from public.accounts), 2,
  'Alice sees exactly her two accounts');

select is(
  (select balance from public.account_balances where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1200.00::numeric, 'bank balance = 1000 + 500 - 200 - 100 transfer out');

select is(
  (select balance from public.account_balances where name = 'Cash'),
  100.00::numeric, 'cash balance = 0 + 100 transfer in');

select is(
  (select total from public.monthly_category_totals where category_name = 'Groceries'),
  200.00::numeric, 'monthly_category_totals sums expenses per category');

select throws_ok(
  $$ insert into public.transactions (account_id, category_id, type, amount)
     select 'aaaaaaaa-0000-0000-0000-000000000001', id, 'expense', 10
     from public.categories where name = 'Salary' $$,
  '23514', null, 'an income category cannot be used for an expense');

select throws_ok(
  $$ insert into public.transactions (account_id, to_account_id, type, amount)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'transfer', 10) $$,
  '23514', null, 'a transfer must go to a different account');

insert into public.savings_goals (id, name, target_amount)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'Laptop', 50000);
insert into public.goal_contributions (goal_id, amount) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 3000),
  ('bbbbbbbb-0000-0000-0000-000000000001', -500);

select is(
  (select saved_amount from public.goal_progress where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  2500.00::numeric, 'goal_progress nets contributions and withdrawals');

-- Daily rule every 2 days starting 4 days ago: due on -4, -2 and today.
insert into public.recurring_rules
  (id, account_id, category_id, type, amount, frequency, "interval", start_date, next_run_on)
select 'cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', id,
       'expense', 50, 'daily', 2, current_date - 4, current_date - 4
from public.categories where name = 'Bills & Utilities';

-- ---------------------------------------------------------------------------
-- Act as Bob
-- ---------------------------------------------------------------------------
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from public.accounts where user_id = '11111111-1111-1111-1111-111111111111'),
  0, 'Bob cannot see Alice''s accounts');

select is(
  (select count(*)::int from public.transactions), 0,
  'Bob cannot see Alice''s transactions');

select is_empty(
  $$ update public.accounts set name = 'hacked'
     where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id $$,
  'Bob cannot update Alice''s account');

select throws_ok(
  $$ insert into public.accounts (user_id, name) values ('11111111-1111-1111-1111-111111111111', 'Sneaky') $$,
  '42501', null, 'Bob cannot create rows owned by Alice');

select throws_ok(
  $$ insert into public.transactions (account_id, category_id, type, amount)
     select 'aaaaaaaa-0000-0000-0000-000000000001', id, 'expense', 1
     from public.categories where name = 'Groceries' $$,
  '23503', null, 'Bob cannot post a transaction to Alice''s account');

select is(public.process_my_recurring_rules(), 0, 'Bob processing his rules does not touch Alice''s');

-- ---------------------------------------------------------------------------
-- Back to postgres: scheduler behaviour and pure date math
-- ---------------------------------------------------------------------------
reset role;

select is(public.process_recurring_rules(), 3, 'scheduler catches up all missed occurrences');

select is(
  (select next_run_on from public.recurring_rules where id = 'cccccccc-0000-0000-0000-000000000001'),
  current_date + 2, 'next_run_on moves past today');

select is(
  public.next_recurring_date('2026-01-31', 'monthly', 1, '2026-01-31'),
  '2026-02-28'::date, 'monthly rule clamps to end of short month');

select is(
  public.next_recurring_date('2026-02-28', 'monthly', 1, '2026-01-31'),
  '2026-03-31'::date, 'monthly rule returns to the anchor day afterwards');

select * from finish();
rollback;
