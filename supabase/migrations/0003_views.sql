-- Read-only views. security_invoker = true makes them run with the caller's
-- permissions, so the RLS policies on the underlying tables still apply.

-- Current balance of each account:
--   initial + income - expense - transfers out + transfers in
create view public.account_balances
with (security_invoker = true) as
select
  a.id,
  a.user_id,
  a.name,
  a.type,
  a.color,
  a.icon,
  a.is_archived,
  a.initial_balance,
  a.initial_balance
    + coalesce(sum(case
        when t.type = 'income'   and t.account_id    = a.id then  t.amount
        when t.type = 'expense'  and t.account_id    = a.id then -t.amount
        when t.type = 'transfer' and t.account_id    = a.id then -t.amount
        when t.type = 'transfer' and t.to_account_id = a.id then  t.amount
      end), 0) as balance
from public.accounts a
left join public.transactions t
  on t.account_id = a.id or t.to_account_id = a.id
group by a.id;

-- Income / expense totals per month and category (transfers excluded).
create view public.monthly_category_totals
with (security_invoker = true) as
select
  t.user_id,
  date_trunc('month', t.occurred_on)::date as month,
  t.category_id,
  c.name  as category_name,
  c.color as category_color,
  c.icon  as category_icon,
  t.type,
  sum(t.amount) as total,
  count(*)      as tx_count
from public.transactions t
join public.categories c on c.id = t.category_id
where t.type in ('income', 'expense')
group by t.user_id, date_trunc('month', t.occurred_on), t.category_id, c.name, c.color, c.icon, t.type;

-- Savings goals with the amount saved so far.
create view public.goal_progress
with (security_invoker = true) as
select
  g.*,
  coalesce(sum(gc.amount), 0)::numeric(14,2) as saved_amount
from public.savings_goals g
left join public.goal_contributions gc on gc.goal_id = g.id
group by g.id;
