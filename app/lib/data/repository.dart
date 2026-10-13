import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import 'models.dart';
import 'offline_store.dart';

/// Outcome of one upload run of queued offline changes.
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

  final _results = StreamController<SyncResult>.broadcast();
  final _reachability = StreamController<bool>.broadcast();
  bool? _reachable;

  /// Every finished upload run, for the sync status shown in the app.
  Stream<SyncResult> get syncResults => _results.stream;

  /// Emits when the server stops or starts answering requests.
  Stream<bool> get reachability => _reachability.stream;

  /// Whether the server answered the latest request (null before the first).
  bool? get isReachable => _reachable;

  void _setReachable(bool value) {
    if (_reachable == value || _reachability.isClosed) return;
    _reachable = value;
    _reachability.add(value);
  }

  void dispose() {
    _results.close();
    _reachability.close();
  }

  /// Runs [fetch] and remembers its rows under [cacheKey] (when given).
  /// Without a connection it returns the rows remembered under [fallbackKey]
  /// (default [cacheKey]), narrowed by [where], or rethrows when there are none.
  Future<List<Map<String, dynamic>>> _read(
    String? cacheKey,
    PostgrestBuilder<List<Map<String, dynamic>>, dynamic, dynamic> Function() fetch, {
    String? fallbackKey,
    bool Function(Map<String, dynamic> row)? where,
  }) async {
    final fallback = fallbackKey ?? cacheKey;
    var request = fetch();
    // The client retries failed reads for several seconds. With saved rows to
    // show instead, one attempt is enough.
    if (fallback != null && _store.hasRows(fallback)) request = request.retry(enabled: false);
    try {
      final rows = await request.timeout(_readTimeout);
      _setReachable(true);
      if (cacheKey != null) await _store.writeRows(cacheKey, rows);
      return rows;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      _setReachable(false);
      final cached = fallback == null ? null : _store.readRows(fallback);
      if (cached == null) rethrow;
      return where == null ? cached : cached.where(where).toList();
    }
  }

  /// Forgets cached rows, e.g. on sign-out. Queued changes are kept.
  Future<void> clearCache() => _store.clearCache();

  List<PendingTxOp> get pendingOps => _store.pendingOps();

  // ---------------------------------------------------------------- profile
  Future<Profile> fetchProfile() async {
    final rows = await _read('profile', () => _db.from('profiles').select().eq('id', _db.auth.currentUser!.id).limit(1));
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
        await _read('accounts', () => _db.from('account_balances').select().order('is_archived').order('name'));
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
    final rows = await _read('categories', () => _db.from('categories').select().order('name'));
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
    // Strip characters that have meaning in PostgREST filter syntax.
    final term = (search ?? '').replaceAll(RegExp(r'[%,()*]'), ' ').trim();
    PostgrestTransformBuilder<PostgrestList> query() {
      var query = _db.from('transactions').select();
      if (from != null) query = query.gte('occurred_on', toDbDate(from));
      if (to != null) query = query.lte('occurred_on', toDbDate(to));
      if (accountId != null) query = query.or('account_id.eq.$accountId,to_account_id.eq.$accountId');
      if (categoryId != null) query = query.eq('category_id', categoryId);
      if (type != null) query = query.eq('type', type.name);
      if (term.isNotEmpty) query = query.ilike('note', '%$term%');
      return query.order('occurred_on', ascending: false).order('created_at', ascending: false).limit(limit);
    }

    bool matches(Transaction tx) =>
        (from == null || !tx.occurredOn.isBefore(dateOnly(from))) &&
        (to == null || !tx.occurredOn.isAfter(dateOnly(to))) &&
        (accountId == null || tx.accountId == accountId || tx.toAccountId == accountId) &&
        (categoryId == null || tx.categoryId == categoryId) &&
        (type == null || tx.type == type) &&
        (term.isEmpty || (tx.note ?? '').toLowerCase().contains(term.toLowerCase()));

    // Only the unfiltered list is cached. Offline, filters and searches are
    // applied to it on the device.
    final unfilteredKey = 'tx:${from == null ? '' : toDbDate(from)}:${to == null ? '' : toDbDate(to)}:$limit';
    final filtered = accountId != null || categoryId != null || type != null || term.isNotEmpty;
    final rows = filtered
        ? await _read(null, query, fallbackKey: unfilteredKey, where: (r) => matches(Transaction.fromJson(r)))
        : await _read(unfilteredKey, query);
    return overlayTransactions(rows.map(Transaction.fromJson).toList(), pendingOps, matches: matches, limit: limit);
  }

  /// Saves on the device first, then tries to upload. Returns true when the
  /// change reached the server and false when it is queued for later. Throws
  /// [SyncRejected] when the server refused it.
  /// [original] is the unedited transaction when editing.
  Future<bool> saveTransaction(Transaction tx, {Transaction? original}) async {
    final saved = await _store.queueSave(tx, original: original);
    return _upload(saved.id!);
  }

  /// Same as [saveTransaction], for a delete.
  Future<bool> deleteTransaction(Transaction tx) async {
    await _store.queueDelete(tx);
    return _upload(tx.id!);
  }

  /// Ids whose save is waiting on [_upload]; their rejections go to that
  /// caller instead of [syncResults].
  final _awaited = <String>{};
  final _rejectedForCaller = <String, String>{};

  Future<bool> _upload(String id) async {
    _awaited.add(id);
    try {
      await syncPending().timeout(const Duration(seconds: 6));
    } on TimeoutException {
      // Still uploading in the background; syncResults reports the outcome.
    } finally {
      _awaited.remove(id);
    }
    final rejection = _rejectedForCaller.remove(id);
    if (rejection != null) throw SyncRejected(rejection);
    return !pendingOps.any((op) => op.id == id);
  }

  Future<SyncResult>? _running;
  Future<SyncResult>? _next;

  /// Uploads queued transaction changes in order. When a run is already in
  /// progress, one more run follows it (shared by everyone who asks
  /// meanwhile), so changes queued in between are never left behind.
  Future<SyncResult> syncPending() {
    final running = _running;
    if (running == null) return _running = _sync().whenComplete(() => _running = null);
    return _next ??= running.then<void>((_) {}, onError: (Object _) {}).then((_) {
      _next = null;
      return syncPending();
    });
  }

  Future<SyncResult> _sync() async {
    var pushed = 0;
    final failures = <String>[];
    // Always works on the head of the queue, so changes queued during the run
    // are included and a change edited mid-upload is sent again.
    while (true) {
      final ops = pendingOps;
      if (ops.isEmpty) break;
      final op = ops.first;
      try {
        await _push(op).timeout(_writeTimeout);
        _setReachable(true);
        await _store.completeOp(op);
        pushed++;
      } catch (e) {
        if (!_isRejection(e)) {
          if (isNetworkError(e)) _setReachable(false);
          break; // offline, or a session problem: keep it queued and retry later
        }
        _setReachable(true);
        await _store.dropOp(op);
        final message = _describeRejection(op, e);
        if (_awaited.contains(op.id)) {
          _rejectedForCaller[op.id] = message;
        } else {
          failures.add(message);
        }
      }
    }
    final result = (pushed: pushed, remaining: pendingOps.length, failures: failures);
    if (!_results.isClosed) _results.add(result);
    return result;
  }

  Future<void> _push(PendingTxOp op) async {
    final table = _db.from('transactions');
    if (op.isDelete) {
      await table.delete().eq('id', op.id);
    } else if (op.isInsert) {
      // Upsert: a retry after a lost response must not fail as a duplicate.
      await table.upsert({...op.after!.toWriteJson(), 'id': op.id});
    } else {
      await table.update(op.after!.toWriteJson()).eq('id', op.id);
    }
  }

  /// Only data errors drop a queued change; anything else (no connection, an
  /// expired session, a server outage) leaves it queued.
  static bool _isRejection(Object e) {
    if (e is! PostgrestException) return false;
    final code = e.code ?? '';
    return code.startsWith('22') || code.startsWith('23') || code == '42501';
  }

  static String _describeRejection(PendingTxOp op, Object e) {
    final reason = e is PostgrestException && e.code == '23503'
        ? 'its account or category no longer exists'
        : 'the server refused it';
    final tx = op.after ?? op.before;
    if (tx == null) return 'Could not save a change: $reason.';
    return 'Could not save the ${tx.type.label.toLowerCase()} of '
        '${centsToDecimal(tx.amount).toStringAsFixed(2)} on ${toDbDate(tx.occurredOn)}: $reason.';
  }

  // ------------------------------------------------------- category totals
  Future<List<CategoryTotal>> fetchCategoryTotals({required DateTime fromMonth, required DateTime toMonth}) async {
    final from = toDbDate(monthStart(fromMonth));
    final to = toDbDate(monthStart(toMonth));
    final rows = await _read('totals:$from:$to',
        () => _db.from('monthly_category_totals').select().gte('month', from).lte('month', to).order('month'));
    final totals = rows.map(CategoryTotal.fromJson).toList();
    final ops = pendingOps;
    if (ops.isEmpty) return totals;
    final categories = {
      for (final row in _store.readRows('categories') ?? const <Map<String, dynamic>>[])
        row['id'] as String: Category.fromJson(row),
    };
    return overlayCategoryTotals(totals, ops, categories, fromMonth: fromMonth, toMonth: toMonth);
  }

  // ---------------------------------------------------------------- budgets
  Future<List<Budget>> fetchBudgets(DateTime month) async {
    final m = toDbDate(monthStart(month));
    final rows = await _read('budgets:$m', () => _db.from('budgets').select().eq('month', m));
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
        await _read('goals', () => _db.from('goal_progress').select().order('is_completed').order('created_at'));
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
    final rows = await _read('contributions:$goalId',
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
    final rows = await _read('recurring',
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
