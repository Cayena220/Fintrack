import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import 'models.dart';

/// Thin wrapper around the Supabase tables. RLS on the server scopes every
/// query to the signed-in user, so no user_id filters are needed here.
class FinanceRepository {
  FinanceRepository(this._db);
  final SupabaseClient _db;

  // ---------------------------------------------------------------- profile
  Future<Profile> fetchProfile() async {
    final row = await _db.from('profiles').select().eq('id', _db.auth.currentUser!.id).single();
    return Profile.fromJson(row);
  }

  Future<void> updateProfile({String? displayName, String? currency}) async {
    await _db.from('profiles').update({
      'display_name': ?displayName,
      'currency': ?currency,
    }).eq('id', _db.auth.currentUser!.id);
  }

  // --------------------------------------------------------------- accounts
  Future<List<Account>> fetchAccounts() async {
    final rows = await _db.from('account_balances').select().order('is_archived').order('name');
    return rows.map(Account.fromJson).toList();
  }

  Future<void> saveAccount(Account account) async {
    final data = account.toWriteJson();
    if (account.id.isEmpty) {
      await _db.from('accounts').insert(data);
    } else {
      await _db.from('accounts').update(data).eq('id', account.id);
    }
  }

  Future<void> deleteAccount(String id) => _db.from('accounts').delete().eq('id', id);

  // ------------------------------------------------------------- categories
  Future<List<Category>> fetchCategories() async {
    final rows = await _db.from('categories').select().order('name');
    return rows.map(Category.fromJson).toList();
  }

  Future<void> saveCategory(Category category) async {
    final data = category.toWriteJson();
    if (category.id.isEmpty) {
      await _db.from('categories').insert(data);
    } else {
      await _db.from('categories').update(data).eq('id', category.id);
    }
  }

  Future<void> deleteCategory(String id) => _db.from('categories').delete().eq('id', id);

  // ----------------------------------------------------------- transactions
  Future<List<Transaction>> fetchTransactions({
    DateTime? from,
    DateTime? to,
    String? accountId,
    String? categoryId,
    TxType? type,
    String? search,
    int limit = 1000,
  }) async {
    var query = _db.from('transactions').select();
    if (from != null) query = query.gte('occurred_on', toDbDate(from));
    if (to != null) query = query.lte('occurred_on', toDbDate(to));
    if (accountId != null) query = query.or('account_id.eq.$accountId,to_account_id.eq.$accountId');
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (type != null) query = query.eq('type', type.name);
    if (search != null && search.trim().isNotEmpty) {
      // Strip characters that have meaning in PostgREST filter syntax.
      final term = search.trim().replaceAll(RegExp(r'[%,()*]'), ' ');
      query = query.ilike('note', '%$term%');
    }
    final rows = await query
        .order('occurred_on', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Transaction.fromJson).toList();
  }

  Future<void> saveTransaction(Transaction tx) async {
    final data = tx.toWriteJson();
    if (tx.id == null) {
      await _db.from('transactions').insert(data);
    } else {
      await _db.from('transactions').update(data).eq('id', tx.id!);
    }
  }

  Future<void> deleteTransaction(String id) => _db.from('transactions').delete().eq('id', id);

  // ------------------------------------------------------- category totals
  Future<List<CategoryTotal>> fetchCategoryTotals({required DateTime fromMonth, required DateTime toMonth}) async {
    final rows = await _db
        .from('monthly_category_totals')
        .select()
        .gte('month', toDbDate(monthStart(fromMonth)))
        .lte('month', toDbDate(monthStart(toMonth)))
        .order('month');
    return rows.map(CategoryTotal.fromJson).toList();
  }

  // ---------------------------------------------------------------- budgets
  Future<List<Budget>> fetchBudgets(DateTime month) async {
    final rows = await _db.from('budgets').select().eq('month', toDbDate(monthStart(month)));
    return rows.map(Budget.fromJson).toList();
  }

  Future<void> saveBudget(Budget budget) async {
    final data = budget.toWriteJson();
    if (budget.id == null) {
      await _db.from('budgets').insert(data);
    } else {
      await _db.from('budgets').update(data).eq('id', budget.id!);
    }
  }

  Future<void> deleteBudget(String id) => _db.from('budgets').delete().eq('id', id);

  /// Copies the previous month's budgets into [month], skipping categories
  /// that already have a budget. Returns how many were copied.
  Future<int> copyBudgetsFromPreviousMonth(DateTime month) async {
    final previous = await fetchBudgets(addMonths(month, -1));
    final existing = (await fetchBudgets(month)).map((b) => b.categoryId).toSet();
    final toCopy = previous.where((b) => !existing.contains(b.categoryId)).toList();
    if (toCopy.isEmpty) return 0;
    await _db.from('budgets').insert([
      for (final b in toCopy)
        Budget(id: null, categoryId: b.categoryId, month: month, amount: b.amount, alertThreshold: b.alertThreshold)
            .toWriteJson(),
    ]);
    return toCopy.length;
  }

  // ------------------------------------------------------------------ goals
  Future<List<SavingsGoal>> fetchGoals() async {
    final rows = await _db.from('goal_progress').select().order('is_completed').order('created_at');
    return rows.map(SavingsGoal.fromJson).toList();
  }

  Future<void> saveGoal(SavingsGoal goal) async {
    final data = goal.toWriteJson();
    if (goal.id == null) {
      await _db.from('savings_goals').insert(data);
    } else {
      await _db.from('savings_goals').update(data).eq('id', goal.id!);
    }
  }

  Future<void> deleteGoal(String id) => _db.from('savings_goals').delete().eq('id', id);

  Future<List<GoalContribution>> fetchContributions(String goalId) async {
    final rows = await _db
        .from('goal_contributions')
        .select()
        .eq('goal_id', goalId)
        .order('contributed_on', ascending: false);
    return rows.map(GoalContribution.fromJson).toList();
  }

  Future<void> addContribution({required String goalId, required int amount, required DateTime date, String? note}) =>
      _db.from('goal_contributions').insert({
        'goal_id': goalId,
        'amount': centsToDecimal(amount),
        'contributed_on': toDbDate(date),
        'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      });

  Future<void> deleteContribution(String id) => _db.from('goal_contributions').delete().eq('id', id);

  // -------------------------------------------------------------- recurring
  Future<List<RecurringRule>> fetchRecurringRules() async {
    final rows = await _db.from('recurring_rules').select().order('is_active', ascending: false).order('next_run_on');
    return rows.map(RecurringRule.fromJson).toList();
  }

  Future<void> saveRecurringRule(RecurringRule rule) async {
    final data = rule.toWriteJson();
    if (rule.id == null) {
      await _db.from('recurring_rules').insert(data);
    } else {
      await _db.from('recurring_rules').update(data).eq('id', rule.id!);
    }
  }

  Future<void> deleteRecurringRule(String id) => _db.from('recurring_rules').delete().eq('id', id);

  /// Posts any of the user's recurring rules that are due today or earlier.
  Future<int> processDueRecurringRules() async {
    final posted = await _db.rpc<int?>('process_my_recurring_rules');
    return posted ?? 0;
  }

  // ------------------------------------------------------------ app updates
  Future<AppVersion?> fetchLatestVersion(String platform) async {
    final row = await _db
        .from('app_versions')
        .select()
        .eq('platform', platform)
        .order('build_number', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : AppVersion.fromJson(row);
  }
}
