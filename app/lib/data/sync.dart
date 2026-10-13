import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

typedef SyncStatus = ({
  /// The device has a network connection.
  bool online,

  /// Transaction changes saved on this device but not yet on the server.
  int pending,

  /// Changes the server refused during the last sync (shown once, then cleared).
  List<String> failures,
});

/// Uploads transactions saved offline: right away, when the connection comes
/// back, when the app returns to the foreground, and every 30 seconds while
/// anything is still queued.
class SyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    ref.watch(currentUserIdProvider); // a different user has a different queue

    final connectivity = Connectivity();
    final sub = connectivity.onConnectivityChanged.listen((r) => _setOnline(_hasNetwork(r)), onError: (_) {});
    connectivity.checkConnectivity().then((r) => _setOnline(_hasNetwork(r)), onError: (_) {});
    final timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (state.pending > 0) sync();
    });
    final lifecycle = AppLifecycleListener(onResume: sync);
    ref.onDispose(() {
      sub.cancel();
      timer.cancel();
      lifecycle.dispose();
    });

    Future.microtask(sync);
    return (online: true, pending: _pendingCount(), failures: const []);
  }

  static bool _hasNetwork(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

  int _pendingCount() =>
      ref.read(currentUserIdProvider) == null ? 0 : ref.read(repositoryProvider).pendingOps.length;

  void _setOnline(bool online) {
    final cameOnline = online && !state.online;
    state = (online: online, pending: state.pending, failures: const []);
    if (cameOnline) sync();
  }

  bool _syncing = false;

  /// Uploads whatever is queued. Safe to call often.
  Future<void> sync() async {
    if (_syncing || ref.read(currentUserIdProvider) == null || _pendingCount() == 0) {
      updatePending();
      return;
    }
    _syncing = true;
    try {
      final result = await ref.read(repositoryProvider).syncPending();
      if (result.pushed > 0 || result.failures.isNotEmpty) reloadData();
      state = (online: state.online, pending: result.remaining, failures: result.failures);
    } catch (e) {
      debugPrint('Sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  /// Re-counts the queue, e.g. after a transaction was saved.
  void updatePending() {
    final pending = _pendingCount();
    if (pending != state.pending) state = (online: state.online, pending: pending, failures: const []);
  }

  /// Reloads everything derived from transactions.
  void reloadData() {
    ref.invalidate(accountsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(categoryTotalsProvider);
    ref.invalidate(budgetsProvider);
    ref.invalidate(goalsProvider);
    ref.invalidate(goalContributionsProvider);
    ref.invalidate(recurringRulesProvider);
    updatePending();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

/// Ids of transactions whose latest change has not reached the server yet.
final pendingTxIdsProvider = Provider<Set<String>>((ref) {
  ref.watch(syncControllerProvider.select((s) => s.pending));
  return {for (final op in ref.read(repositoryProvider).pendingOps) op.id};
});
