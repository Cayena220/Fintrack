-- When someone signs up, create their profile and a starter set of categories.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(new.email, '@', 1)
    )
  );

  insert into public.categories (user_id, name, kind, icon, color)
  values
    (new.id, 'Food & Dining',  'expense', 'restaurant',     4294278144),
    (new.id, 'Groceries',      'expense', 'shopping_cart',  4283215696),
    (new.id, 'Transport',      'expense', 'directions_car', 4280391411),
    (new.id, 'Bills & Utilities','expense','receipt',       4294951175),
    (new.id, 'Rent',           'expense', 'home',           4286141768),
    (new.id, 'Shopping',       'expense', 'shopping_bag',   4293467747),
    (new.id, 'Health',         'expense', 'medical',        4294198070),
    (new.id, 'Entertainment',  'expense', 'movie',          4288423856),
    (new.id, 'Education',      'expense', 'school',         4282339765),
    (new.id, 'Other Expense',  'expense', 'category',       4288585374),
    (new.id, 'Salary',         'income',  'work',           4283215696),
    (new.id, 'Business',       'income',  'store',          4278228616),
    (new.id, 'Gifts',          'income',  'gift',           4294940672),
    (new.id, 'Other Income',   'income',  'category',       4288585374);

  insert into public.accounts (user_id, name, type, icon)
  values (new.id, 'Cash', 'cash', 'wallet');

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
