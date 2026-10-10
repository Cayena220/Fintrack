-- FinTrack core schema.
-- Every user-owned table carries user_id (defaulting to the caller) and a
-- unique (id, user_id) pair so child tables can use composite foreign keys.
-- That guarantees a transaction can only point at the same user's accounts
-- and categories, regardless of RLS.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users on delete cascade,
  display_name  text,
  currency      text not null default 'PHP' check (char_length(currency) = 3),
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- accounts (wallets)
-- ---------------------------------------------------------------------------
create table public.accounts (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users on delete cascade,
  name             text not null check (char_length(name) between 1 and 60),
  type             text not null default 'cash'
                   check (type in ('cash', 'bank', 'ewallet', 'credit')),
  initial_balance  numeric(14,2) not null default 0,
  color            bigint  not null default 4283215696,  -- ARGB int, Flutter Color.value
  icon             text not null default 'wallet',
  is_archived      boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (id, user_id)
);
create index accounts_user_idx on public.accounts (user_id);

-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------
create table public.categories (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  name         text not null check (char_length(name) between 1 and 40),
  kind         text not null check (kind in ('income', 'expense')),
  icon         text not null default 'category',
  color        bigint  not null default 4284513675,
  is_archived  boolean not null default false,
  created_at   timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, kind, name)
);
create index categories_user_idx on public.categories (user_id);

-- ---------------------------------------------------------------------------
-- recurring rules (declared before transactions, which reference them)
-- ---------------------------------------------------------------------------
create table public.recurring_rules (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  account_id   uuid not null,
  category_id  uuid not null,
  type         text not null check (type in ('income', 'expense')),
  amount       numeric(14,2) not null check (amount > 0),
  note         text,
  frequency    text not null check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),
  "interval"   integer not null default 1 check ("interval" between 1 and 365),
  start_date   date not null default current_date,
  next_run_on  date not null default current_date,
  end_date     date,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (id, user_id),
  foreign key (account_id, user_id)  references public.accounts (id, user_id) on delete cascade,
  foreign key (category_id, user_id) references public.categories (id, user_id) on delete cascade,
  check (end_date is null or end_date >= start_date)
);
create index recurring_rules_due_idx on public.recurring_rules (next_run_on) where is_active;

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
create table public.transactions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users on delete cascade,
  account_id         uuid not null,
  category_id        uuid,
  type               text not null check (type in ('income', 'expense', 'transfer')),
  amount             numeric(14,2) not null check (amount > 0),
  occurred_on        date not null default current_date,
  note               text check (note is null or char_length(note) <= 500),
  to_account_id      uuid,
  recurring_rule_id  uuid,
  created_at         timestamptz not null default now(),
  foreign key (account_id, user_id)    references public.accounts (id, user_id) on delete cascade,
  foreign key (to_account_id, user_id) references public.accounts (id, user_id) on delete cascade,
  foreign key (category_id, user_id)   references public.categories (id, user_id) on delete restrict,
  foreign key (recurring_rule_id) references public.recurring_rules (id) on delete set null,
  -- transfers move money between two different accounts and have no category;
  -- income/expense always have a category and no destination account.
  check (
    (type = 'transfer' and category_id is null and to_account_id is not null and to_account_id <> account_id)
    or
    (type <> 'transfer' and category_id is not null and to_account_id is null)
  )
);
create index transactions_user_date_idx on public.transactions (user_id, occurred_on desc);
create index transactions_account_idx on public.transactions (account_id);
create index transactions_to_account_idx on public.transactions (to_account_id);
create index transactions_category_idx on public.transactions (category_id);

-- The category's kind must match the transaction type (no "salary" expenses).
create or replace function public.check_category_kind()
returns trigger
language plpgsql
as $$
declare
  cat_kind text;
begin
  if new.category_id is null then
    return new;
  end if;
  select kind into cat_kind from public.categories where id = new.category_id;
  if cat_kind is distinct from new.type then
    raise exception 'Category kind (%) does not match type (%)', cat_kind, new.type
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger transactions_category_kind
  before insert or update of category_id, type on public.transactions
  for each row execute function public.check_category_kind();

create trigger recurring_rules_category_kind
  before insert or update of category_id, type on public.recurring_rules
  for each row execute function public.check_category_kind();

-- ---------------------------------------------------------------------------
-- budgets (one per expense category per month)
-- ---------------------------------------------------------------------------
create table public.budgets (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users on delete cascade,
  category_id      uuid not null,
  month            date not null check (extract(day from month) = 1),
  amount           numeric(14,2) not null check (amount > 0),
  alert_threshold  numeric(3,2) not null default 0.80 check (alert_threshold > 0 and alert_threshold <= 1),
  created_at       timestamptz not null default now(),
  foreign key (category_id, user_id) references public.categories (id, user_id) on delete cascade,
  unique (user_id, category_id, month)
);
create index budgets_user_month_idx on public.budgets (user_id, month);

-- ---------------------------------------------------------------------------
-- savings goals
-- ---------------------------------------------------------------------------
create table public.savings_goals (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users on delete cascade,
  name           text not null check (char_length(name) between 1 and 60),
  target_amount  numeric(14,2) not null check (target_amount > 0),
  target_date    date,
  icon           text not null default 'savings',
  color          bigint  not null default 4278228616,
  is_completed   boolean not null default false,
  created_at     timestamptz not null default now(),
  unique (id, user_id)
);
create index savings_goals_user_idx on public.savings_goals (user_id);

create table public.goal_contributions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users on delete cascade,
  goal_id         uuid not null,
  amount          numeric(14,2) not null check (amount <> 0),  -- negative = withdrawal
  contributed_on  date not null default current_date,
  note            text,
  created_at      timestamptz not null default now(),
  foreign key (goal_id, user_id) references public.savings_goals (id, user_id) on delete cascade
);
create index goal_contributions_goal_idx on public.goal_contributions (goal_id);
