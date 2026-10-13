import 'package:fintrack/data/models.dart';
import 'package:fintrack/data/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Transaction _tx({
  String? id,
  TxType type = TxType.expense,
  int amount = 1000,
  DateTime? on,
  String account = 'a1',
  String? to,
  String? category = 'c1',
  String? note,
}) =>
    Transaction(
      id: id,
      accountId: account,
      categoryId: type == TxType.transfer ? null : category,
      type: type,
      amount: amount,
      occurredOn: on ?? DateTime(2026, 10, 5),
      note: note,
      toAccountId: to,
      recurringRuleId: null,
    );

const _account = Account(
  id: 'a1',
  name: 'Wallet',
  type: AccountType.cash,
  initialBalance: 0,
  balance: 5000,
  color: 0,
  icon: 'wallet',
  isArchived: false,
);

void main() {
  late OfflineStore store;
  String? user = 'u1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    user = 'u1';
    store = OfflineStore(await SharedPreferences.getInstance(), () => user);
  });

  test('a new transaction gets a UUID and is queued as an insert', () async {
    final saved = await store.queueSave(_tx());
    expect(saved.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    final ops = store.pendingOps();
    expect(ops, hasLength(1));
    expect(ops.single.isInsert, isTrue);
    expect(ops.single.after!.amount, 1000);
  });

  test('editing a queued insert keeps one insert with the latest values', () async {
    final saved = await store.queueSave(_tx());
    await store.queueSave(_tx(id: saved.id, amount: 2500), original: saved);
    final ops = store.pendingOps();
    expect(ops, hasLength(1));
    expect(ops.single.isInsert, isTrue);
    expect(ops.single.after!.amount, 2500);
  });

  test('editing a server transaction remembers the server version', () async {
    final server = _tx(id: 's1');
    await store.queueSave(_tx(id: 's1', amount: 3000), original: server);
    await store.queueSave(_tx(id: 's1', amount: 4000), original: _tx(id: 's1', amount: 3000));
    final op = store.pendingOps().single;
    expect(op.before!.amount, 1000);
    expect(op.after!.amount, 4000);
  });

  test('deleting keeps the server version so balances can be corrected', () async {
    await store.queueDelete(_tx(id: 's1'));
    final op = store.pendingOps().single;
    expect(op.isDelete, isTrue);
    expect(op.before!.id, 's1');
  });

  test('completing an op removes it, unless it was edited during the upload', () async {
    final saved = await store.queueSave(_tx());
    final uploading = store.pendingOps().single;
    await store.queueSave(_tx(id: saved.id, amount: 9000), original: saved);
    await store.completeOp(uploading);
    final op = store.pendingOps().single;
    expect(op.isInsert, isFalse, reason: 'the server now has the first version');
    expect(op.before!.amount, 1000);
    expect(op.after!.amount, 9000);

    await store.completeOp(op);
    expect(store.pendingOps(), isEmpty);
  });

  test('a refused change is dropped, unless it was edited meanwhile', () async {
    final saved = await store.queueSave(_tx());
    final uploading = store.pendingOps().single;
    await store.queueSave(_tx(id: saved.id, amount: 5000), original: saved);
    await store.dropOp(uploading);
    expect(store.pendingOps().single.after!.amount, 5000, reason: 'the edit may fix the problem');
    expect(store.pendingOps().single.isInsert, isTrue);

    await store.dropOp(store.pendingOps().single);
    expect(store.pendingOps(), isEmpty);
  });

  test('clearing the cache keeps the queue', () async {
    await store.queueSave(_tx());
    await store.writeRows('accounts', [
      {'id': 'a1'},
    ]);
    await store.clearCache();
    expect(store.readRows('accounts'), isNull);
    expect(store.pendingOps(), hasLength(1));
  });

  test('network errors and outages are told apart from rejections', () {
    expect(isNetworkError(Exception('ClientException with SocketException: Failed host lookup')), isTrue);
    expect(isNetworkError(const PostgrestException(message: '<html>', code: '503')), isTrue);
    expect(isNetworkError(const PostgrestException(message: 'fk', code: '23503')), isFalse);
    expect(isNetworkError(const PostgrestException(message: 'jwt', code: 'PGRST301')), isFalse);
  });

  test('the queue and cache belong to the signed-in user', () async {
    await store.queueSave(_tx());
    await store.writeRows('accounts', [
      {'id': 'a1'},
    ]);
    user = 'u2';
    expect(store.pendingOps(), isEmpty);
    expect(store.readRows('accounts'), isNull);
    user = 'u1';
    expect(store.pendingOps(), hasLength(1));
    expect(store.readRows('accounts'), hasLength(1));
  });

  group('overlays', () {
    test('transactions: adds, replaces and removes queued changes', () async {
      final fetched = [_tx(id: 's1', on: DateTime(2026, 10, 3)), _tx(id: 's2', on: DateTime(2026, 10, 1))];
      final added = await store.queueSave(_tx(on: DateTime(2026, 10, 2), note: 'offline'));
      await store.queueSave(_tx(id: 's1', amount: 7700, on: DateTime(2026, 10, 3)), original: fetched[0]);
      await store.queueDelete(fetched[1]);

      final list = overlayTransactions(fetched, store.pendingOps());
      expect(list.map((t) => t.id), ['s1', added.id]);
      expect(list.first.amount, 7700);
    });

    test('transactions: respects the filter', () async {
      await store.queueSave(_tx(type: TxType.income, category: 'c2'));
      final list = overlayTransactions(const [], store.pendingOps(), matches: (t) => t.type == TxType.expense);
      expect(list, isEmpty);
    });

    test('balances follow the account_balances view rules', () async {
      await store.queueSave(_tx(amount: 1000)); // expense -10
      await store.queueSave(_tx(type: TxType.income, amount: 300)); // income +3
      await store.queueSave(_tx(type: TxType.transfer, amount: 200, to: 'a1', account: 'a2')); // transfer in +2
      await store.queueDelete(_tx(id: 's9', amount: 500)); // deleted expense +5
      final [account] = overlayBalances(const [_account], store.pendingOps());
      expect(account.balance, 5000 - 1000 + 300 + 200 + 500);
    });

    test('category totals add new rows and drop emptied ones', () async {
      const food = Category(id: 'c1', name: 'Food', kind: TxType.expense, icon: 'restaurant', color: 0, isArchived: false);
      final existing = CategoryTotal(
        month: DateTime(2026, 10),
        categoryId: 'c1',
        categoryName: 'Food',
        categoryColor: 0,
        categoryIcon: 'restaurant',
        type: TxType.expense,
        total: 1000,
        count: 1,
      );
      await store.queueDelete(_tx(id: 's1', amount: 1000));
      var totals = overlayCategoryTotals([existing], store.pendingOps(), {'c1': food},
          fromMonth: DateTime(2026, 10), toMonth: DateTime(2026, 10));
      expect(totals, isEmpty);

      await store.queueSave(_tx(amount: 250));
      await store.queueSave(_tx(amount: 999, on: DateTime(2026, 9, 30))); // outside the range
      totals = overlayCategoryTotals([existing], store.pendingOps(), {'c1': food},
          fromMonth: DateTime(2026, 10), toMonth: DateTime(2026, 10));
      expect(totals.single.total, 250);
      expect(totals.single.count, 1);
    });
  });
}
