import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../data/providers.dart';
import '../../data/sync.dart';
import '../../services/notification_service.dart';
import '../../services/update_service.dart';
import '../budgets/budget_alerts.dart';

const _destinations = [
  (icon: Icons.space_dashboard_outlined, selected: Icons.space_dashboard, label: 'Home'),
  (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Transactions'),
  (icon: Icons.pie_chart_outline, selected: Icons.pie_chart, label: 'Budgets'),
  (icon: Icons.insights_outlined, selected: Icons.insights, label: 'Reports'),
  (icon: Icons.menu, selected: Icons.menu_open, label: 'More'),
];

/// Bottom navigation on phones, a navigation rail on wide windows.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupTasks());
  }

  /// Once per app launch after sign-in: post due recurring items, check
  /// budgets, and look for an app update. Failures are non-fatal.
  Future<void> _runStartupTasks() async {
    final repo = ref.read(repositoryProvider);
    try {
      final posted = await repo.processDueRecurringRules();
      if (posted > 0 && mounted) refreshFinanceData(ref);
    } catch (e) {
      debugPrint('Recurring processing failed: $e');
    }

    await NotificationService.instance.requestPermission();

    try {
      final profile = await ref.read(profileProvider.future);
      await checkBudgetAlerts(repo, profile?.currency ?? 'PHP');
    } catch (e) {
      debugPrint('Budget check failed: $e');
    }

    try {
      final update = await findAvailableUpdate(repo);
      if (update != null && mounted) await showUpdateDialog(context, update);
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  void _go(int index) => widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final index = widget.shell.currentIndex;
    final sync = ref.watch(syncControllerProvider);
    ref.listen(syncControllerProvider.select((s) => s.failures), (_, failures) {
      for (final message in failures) {
        showSnack(context, message);
      }
    });
    final showBanner = !sync.online || sync.pending > 0;
    final body = !showBanner
        ? widget.shell
        : Column(children: [
            _SyncBanner(status: sync, onRetry: () => ref.read(syncControllerProvider.notifier).sync()),
            // The banner already covers the status bar.
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.shell)),
          ]);

    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: index,
          onDestinationSelected: _go,
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FloatingActionButton(
              heroTag: 'rail-add',
              tooltip: 'New transaction',
              elevation: 0,
              onPressed: () => context.push('/transaction'),
              child: const Icon(Icons.add),
            ),
          ),
          destinations: [
            for (final d in _destinations)
              NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }
}

/// Thin strip at the top while offline or while changes wait to upload.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.status, required this.onRetry});

  final SyncStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final waiting = status.pending == 0
        ? ''
        : '${status.pending} ${status.pending == 1 ? 'change' : 'changes'} waiting to sync';
    final text = status.online ? waiting : (waiting.isEmpty ? "You're offline" : "You're offline · $waiting");
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(children: [
            Icon(status.online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined,
                size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer)),
            ),
            if (status.online && status.pending > 0)
              TextButton(onPressed: onRetry, child: const Text('Sync now'))
            else
              const SizedBox(height: 36),
          ]),
        ),
      ),
    );
  }
}
