import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'repository.dart';

@immutable
class SyncStatus {
  const SyncStatus({this.online = true, this.pendingIds = const {}, this.failures = const []});

  /// The device has a connection and the server answered the last request.
  final bool online;

  /// Transactions whose latest change is saved on this device but not yet on
  /// the server.
  final Set<String> pendingIds;

  /// Changes the server refused in the last upload run (shown once).
  final List<String> failures;

  int get pending => pendingIds.length;
}

/// Uploads transactions saved offline: right away, when the connection comes
/// back, when the app returns to the foreground, and every 30 seconds while
/// anything is still queued.
class SyncController extends Notifier<SyncStatus> {
  bool _network = true;
  bool _reachable = true;

  @override
  SyncStatus build() {
    ref.watch(currentUserIdProvider); // a different user has a different queue
    final repo = ref.watch(repositoryProvider);
    _reachable = repo.isReachable ?? _reachable; // requests may have failed before this existed

    final connectivity = Connectivity();
    final subs = <StreamSubscription<Object?>>[
      repo.syncResults.listen(_onResult),
      repo.reachability.listen(_onReachable),
      connectivity.onConnectivityChanged.listen((r) => _onNetwork(_hasNetwork(r)), onError: (Object _) {}),
    ];
    connectivity.checkConnectivity().then((r) => _onNetwork(_hasNetwork(r)), onError: (Object _) {});
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    final lifecycle = AppLifecycleListener(onResume: sync);
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
      timer.cancel();
      lifecycle.dispose();
    });

    Future.microtask(sync);
    return SyncStatus(online: _network && _reachable, pendingIds: _pendingIds());
  }

  static bool _hasNetwork(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

  /// False once the provider is disposed; async callbacks must then do nothing.
  bool get _mounted {
    try {
      return ref.mounted;
    } catch (_) {
      return false;
    }
  }

  Set<String> _pendingIds() => ref.read(currentUserIdProvider) == null
      ? const {}
      : {for (final op in ref.read(repositoryProvider).pendingOps) op.id};

  void _emit({List<String> failures = const []}) {
    if (!_mounted) return;
    state = SyncStatus(online: _network && _reachable, pendingIds: _pendingIds(), failures: failures);
  }

  void _onResult(SyncResult result) {
    if (!_mounted) return;
    if (result.pushed > 0 || result.failures.isNotEmpty) _invalidateData();
    _emit(failures: result.failures);
  }

  void _onReachable(bool reachable) {
    if (!_mounted) return;
    final cameBack = reachable && !_reachable;
    _reachable = reachable;
    _emit();
    if (cameBack) sync();
  }

  void _onNetwork(bool network) {
    if (!_mounted) return;
    final cameBack = network && !_network;
    _network = network;
    _emit();
    if (cameBack) {
      sync();
      _invalidateData(); // swap the saved copies for fresh data
    }
  }

  void _tick() {
    if (!_mounted) return;
    if (state.pending > 0) {
      sync();
    } else if (_network && !_reachable) {
      _invalidateData(); // reloading the open screens checks whether the server is back
    }
  }

  /// Uploads whatever is queued. Safe to call often; the outcome arrives
  /// through the repository's results stream.
  Future<void> sync() async {
    if (!_mounted || ref.read(currentUserIdProvider) == null) return;
    final repo = ref.read(repositoryProvider);
    if (repo.pendingOps.isEmpty) {
      _emit();
      return;
    }
    try {
      await repo.syncPending();
    } catch (e) {
      debugPrint('Sync failed: $e');
    }
  }

  /// Reloads everything derived from transactions, e.g. after a save.
  void reloadData() {
    if (!_mounted) return;
    _invalidateData();
    _emit();
  }

  void _invalidateData() {
    ref.invalidate(accountsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(categoryTotalsProvider);
    ref.invalidate(budgetsProvider);
    ref.invalidate(goalsProvider);
    ref.invalidate(goalContributionsProvider);
    ref.invalidate(recurringRulesProvider);
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
