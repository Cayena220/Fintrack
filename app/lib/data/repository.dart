import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import 'models.dart';
import 'offline_store.dart';

/// Outcome of uploading queued offline changes.
typedef SyncResult = ({int pushed, int remaining, List<String> failures});

/// Thin wrapper around the Supabase tables. RLS on the server scopes every
/// query to the signed-in user, so no user_id filters are needed here.
///
/// Works offline: reads fall back to the last rows fetched, and transaction
/// writes go through a local queue that [syncPending] uploads later.
class FinanceRepository {
  FinanceRepository(this._db, this._store);
  final SupabaseClient _db;
  final OfflineStore _store;

  static const _readTimeout = Duration(seconds: 10);
  static const _writeTimeout = Duration(seconds: 15);

  /// Runs [fetch] and caches its rows under [cacheKey]. Without a connection
  /// it returns the cached rows instead (or rethrows if there are none).
  Future<List<Map<String, dynamic>>> _cached(
      String cacheKey, Future<List<Map<String, dynamic>>> Function() fetch) async {
    try {
      final rows = await fetch().timeout(_readTimeout);
      await _store.writeRows(cacheKey, rows);
      return rows;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = _store.readRows(cacheKey);
      if (cached == null) rethrow;
      return cached;
    }
  }

  List<PendingTxOp> get pendingOps => _store.pendingOps();

  // ---------------------------------------------------------------- profile
  Future<Profile> fetchProfile() async {
    final rows = await _cached('profile', () async => [
          await _db.from('profiles').select().eq('id', _db.auth.currentUser!.id).single(),
        ]);
    return Profile.fromJson(rows.single);
  }

  Future<void> updateProfile({String? displayName, String? currency}) async {
    await _db.from('profiles').update({
      'display_name': ?displayName,
      'currency': ?currency,
    }).eq('id', _db.auth.currentUser!.id);
  }

  // --------------------------------------------------------------- accounts
  Future<List<Account>> fetchAccounts() async {
    final rows =
        await _cached('accounts', () => _db.from('account_balances').select().order('is_archived').order('name'));
    return overlayBalances(rows.map(Account.fromJson).toList(), pendingOps);
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
    final rows = await _cached('categories', () => _db.from('categories').select().order('name'));
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
    final term = search?.trim() ?? '';
    final key = 'tx:${from == null ? '' : toDbDate(from)}:${to == null ? '' : toDbDate(to)}:'
        '${accountId ?? ''}:${categoryId ?? ''}:${type?.name ?? ''}:$term:$limit';
    final rows = await _cached(key, () {
      var query = _db.from('transactions').select();
      if (from != null) query = query.gte('occurred_on', toDbDate(from));
      if (to != null) query = query.lte('occurred_on', toDbDate(to));
      if (accountId != null) query = query.or('account_id.eq.$accountId,to_account_id.eq.$accountId');
      if (categoryId != null) query = query.eq('category_id', categoryId);
      if (type != null) query = query.eq('type', type.name);
      if (term.isNotEmpty) {
        // Strip characters that have meaning in PostgREST filter syntax.
        query = query.ilike('note', '%${term.replaceAll(RegExp(r'[%,()*]'), ' ')}%');
      }
      return query.order('occurred_on', ascending: false).order('created_at', ascending: false).limit(limit);
    });
    bool matches(Transaction tx) =>
        (from == null || !tx.occurredOn.isBefore(dateOnly(from))) &&
        (to == null || !tx.occurredOn.isAfter(dateOnly(to))) &&
        (accountId == null || tx.accountId == accountId || tx.toAccountId == accountId) &&
        (categoryId == null || tx.categoryId == categoryId) &&
        (type == null || tx.type == type) &&
        (term.isEmpty || (tx.note ?? '').toLowerCase().contains(term.toLowerCase()));
    return overlayTransactions(rows.map(Transaction.fromJson).toList(), pendingOps, matches: matches, limit: limit);
  }

  /// Saves on the device first, then tries to upload. Returns true when the
  /// change reached the server, false when it is queued for later.
  /// [original] is the unedited transaction when editing.
  Future<bool> saveTransaction(Transaction tx, {Transaction? original}) async {
    await _store.queueSave(tx, original: original);
    return _trySync();
  }

  /// Same as [saveTransaction], for a delete.
  Future<bool> deleteTransaction(Transaction tx) async {
    await _store.queueDelete(tx);
    return _trySync();
  }

  Future<bool> _trySync() async {
    try {
      final result = await syncPending().timeout(const Duration(seconds: 6));
      return result.remaining == 0;
    } on TimeoutException {
      return false; // keeps uploading in the background
    }
  }

  Future<SyncResult>? _syncing;

  /// Uploads queued transaction changes in order. Stops at the first network
  /// failure; a change the server rejects is dropped and reported.
  Future<SyncResult> syncPending() => _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<SyncResult> _sync() async {
    var pushed = 0;
    final failures = <String>[];
    for (final op in pendingOps) {
      try {
        final table = _db.from('transactions');
        if (op.isDelete) {
          await table.delete().eq('id', op.id).timeout(_writeTimeout);
        } else if (op.isInsert) {
          // Upsert: a retry after a lost response must not fail as a duplicate.
          await table.upsert({...op.after!.toWriteJson(), 'id': op.id}).timeout(_writeTimeout);
        } else {
          await table.update(op.after!.toWriteJson()).eq('id', op.id).timeout(_writeTimeout);
        }
        await _store.completeOp(op);
        pushed++;
      } catch (e) {
        if (!_isRejection(e)) break; // offline or session issue: retry later
        await _store.completeOp(op);
        failures.add(_describeRejection(op, e));
      }
    }
    return (pushed: pushed, remaining: pendingOps.length, failures: failures);
  }

  /// Only data errors drop a queued change; anything else (no connection, an
  /// expired session) leaves it queued.
  static bool _isRejection(Object e) {
    if (e is! PostgrestException) return false;
    final code = e.code ?? '';
    return code.startsWith('22') || code.startsWith('23') || code == '42501';
  }

  static String _describeRejection(PendingTxOp op, Object e) {
    final tx = op.after ?? op.before!;
    final what = '${tx.type.label.toLowerCase()} of ${centsToDecimal(tx.amount).toStringAsFixed(2)} '
        'on ${toDbDate(tx.occurredOn)}';
    final reason = e is PostgrestException && e.code == '23503'
        ? 'its account or category no longer exists'
        : 'the server rejected it';
    return 'Could not sync the $what: $reason.';
  }

  // ------------------------------------------------------- category totals
  Future<List<CategoryTotal>> fetchCategoryTotals({required DateTime fromMonth, required DateTime toMonth}) async {
    final from = toDbDate(monthStart(fromMonth));
    final to = toDbDate(monthStart(toMonth));
    final rows = await _cached('totals:$from:$to',
        () => _db.from('monthly_category_totals').select().gte('month', from).lte('month', to).order('month'));
    final totals = rows.map(CategoryTotal.fromJson).toList();
    final ops = pendingOps;
    if (ops.isEmpty) return totals;
    final categories = {for (final c in await fetchCategories()) c.id: c};
    return overlayCategoryTotals(totals, ops, categories, fromMonth: fromMonth, toMonth: toMonth);
  }

  // ---------------------------------------------------------------- budgets
  Future<List<Budget>> fetchBudgets(DateTime month) async {
    final m = toDbDate(monthStart(month));
    final rows = await _cached('budgets:$m', () => _db.from('budgets').select().eq('month', m));
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
    final rows =
        await _cached('goals', () => _db.from('goal_progress').select().order('is_completed').order('created_at'));
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
    final rows = await _cached('contributions:$goalId',
        () => _db.from('goal_contributions').select().eq('goal_id', goalId).order('contributed_on', ascending: false));
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
    final rows = await _cached('recurring',
        () => _db.from('recurring_rules').select().order('is_active', ascending: false).order('next_run_on'));
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
