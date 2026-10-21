import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';
import '../../data/sync.dart';
import '../../services/notification_service.dart';
import '../../services/update_service.dart';
import '../budgets/budget_alerts.dart';

// The active item shows the same glyph filled.
const _destinations = [
  (icon: Symbols.space_dashboard_rounded, label: 'Home'),
  (icon: Symbols.receipt_long_rounded, label: 'Transactions'),
  (icon: Symbols.pie_chart_rounded, label: 'Budgets'),
  (icon: Symbols.insights_rounded, label: 'Reports'),
  (icon: Symbols.menu_rounded, label: 'More'),
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
      if (failures.isEmpty) return;
      showSnack(context,
          failures.length == 1 ? failures.single : '${failures.length} changes could not be saved. ${failures.first}');
    });
    final showBanner = !sync.online || sync.pending > 0;
    // Same tree with or without the banner, so the tabs keep their state.
    final body = Column(children: [
      if (showBanner) _SyncBanner(status: sync, onRetry: () => ref.read(syncControllerProvider.notifier).sync()),
      Expanded(
        // The banner already covers the status bar.
        child: MediaQuery.removePadding(context: context, removeTop: showBanner, child: widget.shell),
      ),
    ]);

    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: FinColors.of(context).line))),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: _go,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.icon, fill: 1), label: d.label),
            ],
          ),
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
              onPressed: () => context.push('/transaction'),
              child: const Icon(Symbols.add_rounded),
            ),
          ),
          destinations: [
            for (final d in _destinations)
              NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.icon, fill: 1), label: Text(d.label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }
}

/// Thin strip at the top while offline or while changes wait to upload. On
/// deep water: noticeable, not alarming, because being offline is normal.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.status, required this.onRetry});

  final SyncStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = FinColors.of(context);
    final changes = '${status.pending} ${status.pending == 1 ? 'change' : 'changes'}';
    final text = status.online
        ? '$changes waiting to sync'
        : status.pending == 0
            ? "You're offline. Showing saved data."
            : "You're offline. $changes will sync when you reconnect.";
    // Light status-bar icons over the deep strip.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: colors.deep,
        child: SafeArea(
          bottom: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(children: [
                Icon(status.online ? Symbols.cloud_upload_rounded : Symbols.cloud_off_rounded,
                    size: 18, color: colors.foam),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(text, style: Theme.of(context).textTheme.caption.copyWith(color: colors.onDeep)),
                ),
                if (status.online && status.pending > 0)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.foam,
                      backgroundColor: Colors.transparent,
                      minimumSize: const Size(48, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FinRadius.sm)),
                    ),
                    onPressed: onRetry,
                    child: const Text('Sync now'),
                  )
                else
                  const SizedBox(height: 36),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
