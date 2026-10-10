import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
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

    if (!wide) {
      return Scaffold(
        body: widget.shell,
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
        Expanded(child: widget.shell),
      ]),
    );
  }
}
