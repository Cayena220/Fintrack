import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import 'models.dart';

/// True for failures caused by having no (working) connection or the server
/// being unavailable, as opposed to the server rejecting the request.
bool isNetworkError(Object error) {
  if (error is TimeoutException || error is AuthRetryableFetchException) return true;
  if (error is PostgrestException) {
    // Non-JSON error pages (gateway errors, a paused project) carry the HTTP status as the code.
    final status = int.tryParse(error.code ?? '');
    return status != null && status >= 500 && status < 600;
  }
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('HandshakeException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection refused') ||
      text.contains('Connection closed') ||
      text.contains('Network is unreachable');
}

/// Random v4 UUID, so rows created offline already have their final id.
String newUuid() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A queued change the server refused, for example because its account was
/// deleted on another device. It has been removed from the queue.
class SyncRejected implements Exception {
  const SyncRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A transaction change that has not reached the server yet. There is at most
/// one per transaction id: later edits are merged into it.
class PendingTxOp {
  const PendingTxOp({required this.id, required this.before, required this.after});

  final String id;

  /// The version the server has, or null when the transaction was created
  /// offline and the server has never seen it.
  final Transaction? before;

  /// The version to upload, or null when the transaction was deleted.
  final Transaction? after;

  bool get isInsert => before == null;
  bool get isDelete => after == null;

  factory PendingTxOp.fromJson(Map<String, dynamic> j) => PendingTxOp(
        id: j['id'] as String,
        before: j['before'] == null ? null : Transaction.fromJson(j['before'] as Map<String, dynamic>),
        after: j['after'] == null ? null : Transaction.fromJson(j['after'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {'id': id, 'before': before?.toJson(), 'after': after?.toJson()};
}

/// Device-local storage for the signed-in user: the last rows fetched from
/// each query (shown when offline) and the queue of unsynced transactions.
class OfflineStore {
  OfflineStore(this._prefs, this._userId);

  final SharedPreferences _prefs;
  final String? Function() _userId;

  String? _key(String name) {
    final uid = _userId();
    return uid == null ? null : 'offline:$uid:$name';
  }

  // ------------------------------------------------------------------ cache
  List<Map<String, dynamic>>? readRows(String name) {
    final key = _key('cache:$name');
    final raw = key == null ? null : _prefs.getString(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  bool hasRows(String name) {
    final key = _key('cache:$name');
    return key != null && _prefs.containsKey(key);
  }

  Future<void> writeRows(String name, List<Map<String, dynamic>> rows) async {
    final key = _key('cache:$name');
    if (key != null) await _prefs.setString(key, jsonEncode(rows));
  }

  /// Forgets the signed-in user's cached rows (the queue is kept).
  Future<void> clearCache() async {
    final prefix = _key('cache:');
    if (prefix == null) return;
    for (final key in _prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await _prefs.remove(key);
    }
  }

  // ----------------------------------------------------------------- outbox
  List<PendingTxOp> pendingOps() {
    final key = _key('outbox');
    final raw = key == null ? null : _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) PendingTxOp.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeOps(List<PendingTxOp> ops) async {
    final key = _key('outbox');
    if (key == null) return;
    if (ops.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, jsonEncode([for (final op in ops) op.toJson()]));
    }
  }

  /// Queues a new or edited transaction and returns it with its id.
  /// [original] is the server version when editing an existing transaction.
  Future<Transaction> queueSave(Transaction tx, {Transaction? original}) async {
    final ops = pendingOps().toList();
    final id = tx.id ?? newUuid();
    final saved = tx.id == null ? tx.copyWithId(id) : tx;
    final i = ops.indexWhere((op) => op.id == id);
    if (i >= 0) {
      ops[i] = PendingTxOp(id: id, before: ops[i].before, after: saved);
    } else {
      ops.add(PendingTxOp(id: id, before: tx.id == null ? null : (original ?? saved), after: saved));
    }
    await _writeOps(ops);
    return saved;
  }

  Future<void> queueDelete(Transaction tx) async {
    final ops = pendingOps().toList();
    final i = ops.indexWhere((op) => op.id == tx.id);
    if (i < 0) {
      ops.add(PendingTxOp(id: tx.id!, before: tx, after: null));
    } else {
      // Keeps a delete queued even for a transaction created offline: its
      // upload may already be in flight. Deleting a missing row is harmless.
      ops[i] = PendingTxOp(id: tx.id!, before: ops[i].before, after: null);
    }
    await _writeOps(ops);
  }

  static bool _same(PendingTxOp a, PendingTxOp b) => jsonEncode(a.toJson()) == jsonEncode(b.toJson());

  /// Removes [op] once it is on the server, unless it was edited meanwhile.
  Future<void> completeOp(PendingTxOp op) async {
    final ops = pendingOps().toList();
    final i = ops.indexWhere((o) => o.id == op.id);
    if (i < 0) return;
    if (_same(ops[i], op)) {
      ops.removeAt(i);
    } else {
      // Edited while uploading: the server now has op.after as its version.
      ops[i] = PendingTxOp(id: op.id, before: op.after, after: ops[i].after);
    }
    await _writeOps(ops);
  }

  /// Removes [op] after the server refused it. An edit made meanwhile stays
  /// queued, since it may fix the problem.
  Future<void> dropOp(PendingTxOp op) async {
    final ops = pendingOps().toList();
    final i = ops.indexWhere((o) => o.id == op.id);
    if (i < 0 || !_same(ops[i], op)) return;
    ops.removeAt(i);
    await _writeOps(ops);
  }
}

// --------------------------------------------------------------- overlays
// Server data does not include queued changes yet, so they are applied on top
// of every list and total the app shows.

/// Applies queued changes to a fetched transaction list.
List<Transaction> overlayTransactions(
  List<Transaction> fetched,
  List<PendingTxOp> ops, {
  bool Function(Transaction tx)? matches,
  int? limit,
}) {
  if (ops.isEmpty) return fetched;
  final byId = {for (final op in ops) op.id: op};
  final pendingFirst = <Transaction>[
    for (final op in ops.reversed)
      if (!op.isDelete && (matches == null || matches(op.after!))) op.after!,
  ];
  final rest = [for (final tx in fetched) if (!byId.containsKey(tx.id)) tx];
  final merged = [...pendingFirst, ...rest];
  // Stable sort: newest day first, queued items first within a day.
  final indexed = merged.asMap().entries.toList()
    ..sort((a, b) {
      final byDate = b.value.occurredOn.compareTo(a.value.occurredOn);
      return byDate != 0 ? byDate : a.key.compareTo(b.key);
    });
  final sorted = [for (final e in indexed) e.value];
  return limit != null && sorted.length > limit ? sorted.sublist(0, limit) : sorted;
}

/// Each queued change as (transaction, +1 to add its effect / -1 to remove it).
Iterable<(Transaction, int)> _effects(List<PendingTxOp> ops) sync* {
  for (final op in ops) {
    if (op.before != null) yield (op.before!, -1);
    if (op.after != null) yield (op.after!, 1);
  }
}

/// Adjusts account balances for queued changes (same rules as the
/// account_balances view).
List<Account> overlayBalances(List<Account> accounts, List<PendingTxOp> ops) {
  if (ops.isEmpty) return accounts;
  final delta = <String, int>{};
  for (final (tx, sign) in _effects(ops)) {
    switch (tx.type) {
      case TxType.income:
        delta.update(tx.accountId, (v) => v + sign * tx.amount, ifAbsent: () => sign * tx.amount);
      case TxType.expense:
      case TxType.transfer:
        delta.update(tx.accountId, (v) => v - sign * tx.amount, ifAbsent: () => -sign * tx.amount);
    }
    if (tx.type == TxType.transfer && tx.toAccountId != null) {
      delta.update(tx.toAccountId!, (v) => v + sign * tx.amount, ifAbsent: () => sign * tx.amount);
    }
  }
  return [
    for (final a in accounts)
      delta[a.id] == null
          ? a
          : Account(
              id: a.id,
              name: a.name,
              type: a.type,
              initialBalance: a.initialBalance,
              balance: a.balance + delta[a.id]!,
              color: a.color,
              icon: a.icon,
              isArchived: a.isArchived,
            ),
  ];
}

/// Adjusts monthly category totals for queued changes (same rules as the
/// monthly_category_totals view).
List<CategoryTotal> overlayCategoryTotals(
  List<CategoryTotal> totals,
  List<PendingTxOp> ops,
  Map<String, Category> categories, {
  required DateTime fromMonth,
  required DateTime toMonth,
}) {
  if (ops.isEmpty) return totals;
  final from = monthStart(fromMonth);
  final to = monthStart(toMonth);
  final rows = {for (final t in totals) (t.month, t.categoryId): t};
  for (final (tx, sign) in _effects(ops)) {
    if (tx.type == TxType.transfer || tx.categoryId == null) continue;
    final month = monthStart(tx.occurredOn);
    if (month.isBefore(from) || month.isAfter(to)) continue;
    final key = (month, tx.categoryId!);
    final existing = rows[key];
    final category = categories[tx.categoryId];
    if (existing == null && category == null) continue;
    rows[key] = CategoryTotal(
      month: month,
      categoryId: tx.categoryId!,
      categoryName: existing?.categoryName ?? category!.name,
      categoryColor: existing?.categoryColor ?? category!.color,
      categoryIcon: existing?.categoryIcon ?? category!.icon,
      type: tx.type,
      total: (existing?.total ?? 0) + sign * tx.amount,
      count: (existing?.count ?? 0) + sign,
    );
  }
  return [
    for (final t in rows.values)
      if (t.count > 0) t,
  ]..sort((a, b) => a.month.compareTo(b.month));
}
