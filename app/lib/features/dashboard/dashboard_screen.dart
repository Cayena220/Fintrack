import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../budgets/budget_logic.dart';
import '../budgets/budgets_screen.dart';
import '../transactions/transaction_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final accounts = ref.watch(accountsProvider);
    final month = monthStart(DateTime.now());
    final wide = MediaQuery.sizeOf(context).width >= 840;

    final firstName = (profile?.displayName ?? '').split(' ').first;

    return Scaffold(
      appBar: AppBar(
        title: Text(firstName.isEmpty ? 'Overview' : 'Hi, $firstName'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/transaction'),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshFinanceData(ref);
          ref.invalidate(profileProvider);
          await ref.read(accountsProvider.future);
        },
        child: AsyncView(
          value: accounts,
          onRetry: () => ref.invalidate(accountsProvider),
          builder: (accounts) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ContentWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _BalanceCard(accounts: accounts, month: month),
                  _BudgetWarnings(month: month),
                  SectionHeader('Accounts',
                      action: TextButton(onPressed: () => context.push('/accounts'), child: const Text('Manage'))),
                  _AccountsStrip(accounts: accounts.where((a) => !a.isArchived).toList()),
                  const _GoalsPreview(),
                  SectionHeader('Recent transactions',
                      action: TextButton(onPressed: () => context.go('/transactions'), child: const Text('See all'))),
                  const _RecentTransactions(),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.accounts, required this.month});

  final List<Account> accounts;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = ref.watch(currencyProvider);
    final total = accounts.where((a) => !a.isArchived).fold<int>(0, (sum, a) => sum + a.balance);
    final totals = ref.watch(categoryTotalsProvider((from: month, to: month))).value ?? const [];
    final income = totals.where((t) => t.type == TxType.income).fold<int>(0, (s, t) => s + t.total);
    final expense = totals.where((t) => t.type == TxType.expense).fold<int>(0, (s, t) => s + t.total);

    final onPrimary = theme.colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, Color.lerp(theme.colorScheme.primary, Colors.black, 0.25)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Total balance', style: theme.textTheme.bodyMedium?.copyWith(color: onPrimary.withValues(alpha: 0.85))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(formatMoney(total, currency),
              style: theme.textTheme.headlineMedium?.copyWith(color: onPrimary, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 16),
        Text(formatMonth(month), style: theme.textTheme.labelMedium?.copyWith(color: onPrimary.withValues(alpha: 0.85))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _MiniStat(label: 'Income', value: formatMoney(income, currency), icon: Icons.south_west)),
          const SizedBox(width: 12),
          Expanded(child: _MiniStat(label: 'Expenses', value: formatMoney(expense, currency), icon: Icons.north_east)),
          const SizedBox(width: 12),
          Expanded(child: _MiniStat(label: 'Net', value: formatMoney(income - expense, currency, signed: true), icon: Icons.balance)),
        ]),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: onPrimary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: onPrimary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: onPrimary, fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(color: onPrimary, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _BudgetWarnings extends ConsumerWidget {
  const _BudgetWarnings({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(budgetStatusProvider(month)).value ?? const <BudgetStatus>[];
    final alerts = statuses.where((s) => s.level != BudgetLevel.ok).toList();
    if (alerts.isEmpty) return const SizedBox.shrink();
    final currency = ref.watch(currencyProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: MoneyColors.warning(context).withValues(alpha: 0.12),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('/budgets'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.warning_amber_rounded, color: MoneyColors.warning(context)),
                const SizedBox(width: 8),
                Text('Budget alerts', style: Theme.of(context).textTheme.titleSmall),
              ]),
              const SizedBox(height: 6),
              for (final s in alerts.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.level == BudgetLevel.over
                        ? '${s.category?.name ?? 'Category'} is over by ${formatMoney(-s.remaining, currency)}'
                        : '${s.category?.name ?? 'Category'}: ${(s.ratio * 100).round()}% used, '
                            '${formatMoney(s.remaining, currency)} left',
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AccountsStrip extends ConsumerWidget {
  const _AccountsStrip({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == accounts.length) {
            return SizedBox(
              width: 120,
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/account'),
                  child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add),
                    SizedBox(height: 4),
                    Text('Add account'),
                  ])),
                ),
              ),
            );
          }
          final a = accounts[i];
          return SizedBox(
            width: 170,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/account', extra: a),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      IconBadge(icon: a.icon, color: a.color, size: 30),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                    ]),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: MoneyText(a.balance, currency: currency, signed: false, neutral: a.balance >= 0,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GoalsPreview extends ConsumerWidget {
  const _GoalsPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = (ref.watch(goalsProvider).value ?? const <SavingsGoal>[]).where((g) => !g.isCompleted).take(2).toList();
    if (goals.isEmpty) return const SizedBox.shrink();
    final currency = ref.watch(currencyProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Savings goals',
          action: TextButton(onPressed: () => context.push('/goals'), child: const Text('See all'))),
      for (final g in goals)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => context.push('/goals'),
              leading: IconBadge(icon: g.icon, color: g.color),
              title: Text(g.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: g.progress, minHeight: 6, color: Color(g.color)),
                ),
              ),
              trailing: Text('${formatMoney(g.savedAmount, currency, compact: true)} / '
                  '${formatMoney(g.targetAmount, currency, compact: true)}'),
            ),
          ),
        ),
    ]);
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(recentTransactionsProvider),
      onRetry: () => ref.invalidate(recentTransactionsProvider),
      builder: (txs) => txs.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              message: 'Add your first income or expense to get started.',
              action: FilledButton.icon(
                onPressed: () => context.push('/transaction'),
                icon: const Icon(Icons.add),
                label: const Text('Add transaction'),
              ),
            )
          : Card(
              child: Column(children: [for (final tx in txs) TransactionTile(tx: tx, showDate: true)]),
            ),
    );
  }
}
