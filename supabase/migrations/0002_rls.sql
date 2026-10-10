-- Row Level Security: every user sees and changes only their own rows.

alter table public.profiles           enable row level security;
alter table public.accounts           enable row level security;
alter table public.categories         enable row level security;
alter table public.recurring_rules    enable row level security;
alter table public.transactions       enable row level security;
alter table public.budgets            enable row level security;
alter table public.savings_goals      enable row level security;
alter table public.goal_contributions enable row level security;

-- profiles are keyed by id (= auth.uid()) and created by the signup trigger.
create policy "profiles: read own"   on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "profiles: update own" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Same four policies for every user_id-owned table.
do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts', 'categories', 'recurring_rules', 'transactions',
    'budgets', 'savings_goals', 'goal_contributions'
  ]
  loop
    execute format(
      'create policy "%1$s: select own" on public.%1$I for select to authenticated using (user_id = (select auth.uid()))', t);
    execute format(
      'create policy "%1$s: insert own" on public.%1$I for insert to authenticated with check (user_id = (select auth.uid()))', t);
    execute format(
      'create policy "%1$s: update own" on public.%1$I for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format(
      'create policy "%1$s: delete own" on public.%1$I for delete to authenticated using (user_id = (select auth.uid()))', t);
  end loop;
end;
$$;
