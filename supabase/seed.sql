-- Local development data, loaded by `npx supabase db reset`.
-- Sign in to the app with:  demo@fintrack.local / password123
-- Never run this against the hosted project.

do $$
declare
  uid       uuid := 'dddddddd-0000-0000-0000-000000000001';
  cash      uuid;
  bank      uuid := 'dddddddd-0000-0000-0000-0000000000a1';
  gcash     uuid := 'dddddddd-0000-0000-0000-0000000000a2';
  card      uuid := 'dddddddd-0000-0000-0000-0000000000a3';
  goal      uuid := 'dddddddd-0000-0000-0000-0000000000b1';
  this_month date := date_trunc('month', current_date)::date;
  cat       jsonb;
  m         integer;
  d         date;
begin
  -- The signup trigger creates the profile, default categories and Cash.
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
    'demo@fintrack.local', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{"full_name":"Demo User"}', now(), now(),
    '', '', '', ''
  );

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', 'demo@fintrack.local', 'email_verified', true),
    'email', now(), now(), now()
  );

  select id into cash from public.accounts where user_id = uid and name = 'Cash';
  select jsonb_object_agg(name, id) into cat from public.categories where user_id = uid;

  insert into public.accounts (id, user_id, name, type, initial_balance, color, icon) values
    (bank,  uid, 'BDO Savings', 'bank',    85000,  4280391411, 'bank'),
    (gcash, uid, 'GCash',       'ewallet', 3500,   4278228616, 'phone'),
    (card,  uid, 'Credit card', 'credit',  -4200,  4293467747, 'card');
  update public.accounts set initial_balance = 2500 where id = cash;

  -- Three months of history ending today.
  for m in 0..2 loop
    d := (this_month - make_interval(months => m))::date;

    insert into public.transactions (user_id, account_id, category_id, type, amount, occurred_on, note) values
      (uid, bank,  (cat->>'Salary')::uuid,            'income',  42000, d + 14, 'Salary'),
      (uid, bank,  (cat->>'Rent')::uuid,              'expense', 15000, d + 1,  'Apartment rent'),
      (uid, gcash, (cat->>'Bills & Utilities')::uuid, 'expense', 2850 + m * 120, d + 9, 'Meralco'),
      (uid, gcash, (cat->>'Bills & Utilities')::uuid, 'expense', 1699, d + 11, 'Fiber internet'),
      (uid, cash,  (cat->>'Groceries')::uuid,         'expense', 3200 - m * 150, d + 5,  'Weekly groceries'),
      (uid, cash,  (cat->>'Groceries')::uuid,         'expense', 2750, d + 19, 'Weekly groceries'),
      (uid, cash,  (cat->>'Food & Dining')::uuid,     'expense', 680,  d + 3,  'Lunch with team'),
      (uid, card,  (cat->>'Food & Dining')::uuid,     'expense', 1450 + m * 300, d + 16, 'Dinner out'),
      (uid, gcash, (cat->>'Transport')::uuid,         'expense', 950,  d + 7,  'Grab rides'),
      (uid, card,  (cat->>'Shopping')::uuid,          'expense', 2300 + m * 500, d + 21, 'Clothes'),
      (uid, card,  (cat->>'Entertainment')::uuid,     'expense', 549,  d + 2,  'Netflix');

    insert into public.transactions (user_id, account_id, to_account_id, type, amount, occurred_on, note)
    values (uid, bank, gcash, 'transfer', 5000, d + 15, 'Top up GCash');
  end loop;

  -- Future-dated rows from the loops above would look odd; drop them.
  delete from public.transactions where user_id = uid and occurred_on > current_date;

  insert into public.budgets (user_id, category_id, month, amount, alert_threshold) values
    (uid, (cat->>'Food & Dining')::uuid, this_month, 2500, 0.80),
    (uid, (cat->>'Groceries')::uuid,     this_month, 7000, 0.80),
    (uid, (cat->>'Shopping')::uuid,      this_month, 2000, 0.75),
    (uid, (cat->>'Transport')::uuid,     this_month, 1500, 0.80);

  insert into public.savings_goals (id, user_id, name, target_amount, target_date, icon, color) values
    (goal, uid, 'Emergency fund', 100000, (this_month + interval '1 year')::date, 'emergency', 4294940672);
  insert into public.savings_goals (user_id, name, target_amount, icon, color) values
    (uid, 'New laptop', 65000, 'laptop', 4283215696);

  insert into public.goal_contributions (user_id, goal_id, amount, contributed_on, note) values
    (uid, goal, 10000, current_date - 60, 'Starting amount'),
    (uid, goal, 5000,  current_date - 30, null),
    (uid, goal, 5000,  current_date - 1,  null);

  -- next_run_on is in the future so `db reset` does not post anything; set it
  -- to yesterday to test `select public.process_recurring_rules();`.
  insert into public.recurring_rules
    (user_id, account_id, category_id, type, amount, note, frequency, start_date, next_run_on) values
    (uid, card,  (cat->>'Entertainment')::uuid, 'expense', 549,  'Netflix', 'monthly',
     this_month + 2, case when current_date < this_month + 2 then this_month + 2
                          else (this_month + interval '1 month')::date + 2 end),
    (uid, bank,  (cat->>'Salary')::uuid,        'income',  42000, 'Salary', 'monthly',
     this_month + 14, case when current_date < this_month + 14 then this_month + 14
                           else (this_month + interval '1 month')::date + 14 end);
end;
$$;
