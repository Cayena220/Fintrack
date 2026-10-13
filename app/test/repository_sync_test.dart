import 'dart:async';
import 'dart:convert';

import 'package:fintrack/data/models.dart';
import 'package:fintrack/data/offline_store.dart';
import 'package:fintrack/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Just enough of PostgREST's transactions endpoint to exercise syncing.
class _FakeServer {
  bool online = true;

  /// Answer writes with this Postgres error code instead of applying them.
  String? rejectCode;

  /// Answer every request with this HTTP status and an HTML body.
  int? outageStatus;

  /// Requests wait for this before being answered (when set).
  Future<void>? gate;

  final rows = <String, Map<String, dynamic>>{};
  final writes = <String>[];

  late final client = MockClient((request) async {
    if (!online) throw http.ClientException('SocketException: Failed host lookup: test.supabase.co');
    if (gate != null) await gate;
    // postgrest reads the request back from the response, as with a real one.
    http.Response reply(String body, int status) =>
        http.Response(body, status, request: request, headers: {'content-type': 'application/json'});
    if (outageStatus != null) return reply('<html>Service Unavailable</html>', outageStatus!);

    final id = request.url.queryParameters['id']?.replaceFirst('eq.', '');
    if (request.method != 'GET') {
      writes.add('${request.method} ${id ?? (jsonDecode(request.body) as Map)['id']}');
      if (rejectCode != null) {
        return reply(jsonEncode({'code': rejectCode, 'message': 'rejected', 'details': null, 'hint': null}), 409);
      }
    }
    switch (request.method) {
      case 'GET':
        return reply(jsonEncode(rows.values.toList()), 200);
      case 'POST':
        final row = jsonDecode(request.body) as Map<String, dynamic>;
        rows[row['id'] as String] = row;
        return reply('', 201);
      case 'PATCH':
        rows[id!] = {...rows[id]!, ...jsonDecode(request.body) as Map<String, dynamic>};
        return reply('', 204);
      case 'DELETE':
        rows.remove(id);
        return reply('', 204);
    }
    return reply('', 405);
  });
}

Transaction _tx({String? id, int amount = 1000, TxType type = TxType.expense, String? note}) => Transaction(
      id: id,
      accountId: 'a1',
      categoryId: type == TxType.transfer ? null : 'c1',
      type: type,
      amount: amount,
      occurredOn: DateTime(2026, 10, 5),
      note: note,
      toAccountId: type == TxType.transfer ? 'a2' : null,
      recurringRuleId: null,
    );

void main() {
  late _FakeServer server;
  late OfflineStore store;
  late FinanceRepository repo;

  Future<List<Transaction>> october({TxType? type}) =>
      repo.fetchTransactions(from: DateTime(2026, 10), to: DateTime(2026, 10, 31), type: type);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _FakeServer();
    store = OfflineStore(await SharedPreferences.getInstance(), () => 'u1');
    final db = SupabaseClient(
      'https://test.supabase.co',
      'publishable-key',
      httpClient: server.client,
      accessToken: () async => 'token',
    );
    repo = FinanceRepository(db, store);
  });

  tearDown(() => repo.dispose());

  test('online, a save goes straight to the server', () async {
    expect(await repo.saveTransaction(_tx()), isTrue);
    expect(server.rows, hasLength(1));
    expect(repo.pendingOps, isEmpty);
  });

  test('offline, a save is kept on the device and shown, then uploaded with the same id', () async {
    await october(); // caches the month while online
    server.online = false;

    expect(await repo.saveTransaction(_tx(note: 'lunch')), isFalse);
    final pendingId = repo.pendingOps.single.id;
    final watch = Stopwatch()..start();
    final shown = await october();
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)), reason: 'no waiting through client retries');
    expect(shown.single.id, pendingId);
    expect(shown.single.note, 'lunch');
    expect(server.rows, isEmpty);

    server.online = true;
    final result = await repo.syncPending();
    expect(result.pushed, 1);
    expect(server.rows.keys, [pendingId]);
    expect(repo.pendingOps, isEmpty);
    expect((await october()).single.id, pendingId);
  });

  test('offline, filters and searches use the cached month', () async {
    server.rows['s1'] = {..._tx(type: TxType.income, note: 'Salary').toJson(), 'id': 's1'};
    server.rows['s2'] = {..._tx(note: 'Groceries').toJson(), 'id': 's2'};
    await october();
    server.online = false;

    expect((await october(type: TxType.income)).map((t) => t.id), ['s1']);
    final found = await repo.fetchTransactions(from: DateTime(2026, 10), to: DateTime(2026, 10, 31), search: 'grocer');
    expect(found.map((t) => t.id), ['s2']);
  });

  test('a save the server refuses throws and is not kept', () async {
    server.rejectCode = '23503';
    await expectLater(
      repo.saveTransaction(_tx()),
      throwsA(isA<SyncRejected>().having((e) => e.message, 'message', contains('no longer exists'))),
    );
    expect(repo.pendingOps, isEmpty);
  });

  test('a queued change refused later is reported through syncResults', () async {
    server.online = false;
    await repo.saveTransaction(_tx());
    server
      ..online = true
      ..rejectCode = '23514';

    final reported = repo.syncResults.first;
    await repo.syncPending();
    final result = await reported;
    expect(result.failures.single, contains('refused'));
    expect(repo.pendingOps, isEmpty);
  });

  test('a server outage or session problem keeps the change queued', () async {
    await store.queueSave(_tx());

    server.outageStatus = 503;
    final reachability = repo.reachability.first;
    expect((await repo.syncPending()).remaining, 1);
    expect(await reachability, isFalse);

    server
      ..outageStatus = null
      ..rejectCode = 'PGRST301'; // expired JWT
    expect((await repo.syncPending()).remaining, 1);

    server.rejectCode = null;
    expect((await repo.syncPending()).remaining, 0);
    expect(server.rows, hasLength(1));
  });

  test('a server outage falls back to the cached rows for reads', () async {
    server.rows['s1'] = {..._tx().toJson(), 'id': 's1'};
    await october();
    server.outageStatus = 503;
    expect((await october()).single.id, 's1');
  });

  test('changes queued or edited during an upload are uploaded too', () async {
    final gate = Completer<void>();
    server.gate = gate.future;
    final first = await store.queueSave(_tx());
    final run = repo.syncPending();
    await pumpEventQueue();

    await store.queueSave(_tx(id: first.id, amount: 2500), original: first); // edited mid-upload
    final second = await store.queueSave(_tx(amount: 300));
    final again = repo.syncPending();
    gate.complete();
    await Future.wait([run, again]);

    expect(server.rows[first.id]!['amount'], 25.0);
    expect(server.rows[second.id], isNotNull);
    expect(repo.pendingOps, isEmpty);
  });

  test('deleting a transaction that never reached the server leaves nothing behind', () async {
    await october(); // caches the month while online
    server.online = false;
    await repo.saveTransaction(_tx());
    final queued = repo.pendingOps.single.after!;
    expect(await repo.deleteTransaction(queued), isFalse);
    expect(await october(), isEmpty, reason: 'hidden while the delete is queued');

    server.online = true;
    await repo.syncPending();
    expect(server.rows, isEmpty);
    expect(server.writes, ['DELETE ${queued.id}']);
    expect(repo.pendingOps, isEmpty);
  });
}
