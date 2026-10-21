import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

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
            icon: const Icon(Symbols.settings_rounded),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/transaction'),
              icon: const Icon(Symbols.add_rounded),
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

/// Solid deep water with the logo's foam wave in the corner.
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.accounts, required this.month});

  final List<Account> accounts;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FinColors.of(context);
    final text = Theme.of(context).textTheme;
    final currency = ref.watch(currencyProvider);
    final total = accounts.where((a) => !a.isArchived).fold<int>(0, (sum, a) => sum + a.balance);
    final totals = ref.watch(categoryTotalsProvider((from: month, to: month))).value ?? const [];
    final income = totals.where((t) => t.type == TxType.income).fold<int>(0, (s, t) => s + t.total);
    final expense = totals.where((t) => t.type == TxType.expense).fold<int>(0, (s, t) => s + t.total);
    final net = income - expense;
    final divider = VerticalDivider(width: 1, thickness: 1, color: colors.lineOnDeep);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.deep, borderRadius: BorderRadius.circular(FinRadius.xl)),
      child: Stack(children: [
        Positioned(right: -8, top: 14, width: 192, height: 56, child: CustomPaint(painter: _WavePainter(colors.foam))),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total balance', style: text.caption.copyWith(color: colors.onDeepMuted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatMoney(total, currency),
                  style: text.balance.copyWith(color: total < 0 ? colors.onDeepExpense : colors.onDeep)),
            ),
            const SizedBox(height: 20),
            Text(formatMonth(month), style: text.micro.copyWith(color: colors.onDeepMuted)),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Income',
                    icon: Symbols.south_west_rounded,
                    value: formatMoney(income, currency, signed: true),
                    color: colors.foam,
                    padding: const EdgeInsetsDirectional.only(end: 12),
                  ),
                ),
                divider,
                Expanded(
                  child: _MiniStat(
                    label: 'Expenses',
                    icon: Symbols.north_east_rounded,
                    value: formatMoney(-expense, currency),
                    color: colors.onDeep,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                divider,
                Expanded(
                  child: _MiniStat(
                    label: 'Net',
                    icon: Symbols.balance_rounded,
                    value: formatMoney(net, currency, signed: true),
                    color: net < 0 ? colors.onDeepExpense : colors.foam,
                    padding: const EdgeInsetsDirectional.only(start: 12),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.padding,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = FinColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: colors.onDeepMuted),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: text.micro.copyWith(color: colors.onDeepMuted), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, style: text.bodyStrong.tabular.copyWith(color: color)),
        ),
      ]),
    );
  }
}

/// The logo's wave line at a 48px pitch: the balance card's signature, and
/// the one decorative mark in the UI. Drawn in a 192 × 56 box.
class _WavePainter extends CustomPainter {
  const _WavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 192, size.height / 56);
    void wave({required double x, required double y, required double lift, required int halves,
        required double width, required double opacity}) {
      final path = Path()..moveTo(x, y);
      for (var i = 0; i < halves; i++) {
        path.quadraticBezierTo(x + 48 * i + 24, y + (i.isEven ? -lift : lift), x + 48 * (i + 1), y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color.withValues(alpha: opacity),
      );
    }

    wave(x: 12, y: 22, lift: 17, halves: 4, width: 6, opacity: 0.45);
    wave(x: 36, y: 42, lift: 13, halves: 3, width: 4, opacity: 0.25);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.color != color;
}

/// Budgets past their threshold. Warning-soft while close, expense-soft once
/// anything is over; tapping opens Budgets.
class _BudgetWarnings extends ConsumerWidget {
  const _BudgetWarnings({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(budgetStatusProvider(month)).value ?? const <BudgetStatus>[];
    final alerts = statuses.where((s) => s.level != BudgetLevel.ok).toList();
    if (alerts.isEmpty) return const SizedBox.shrink();
    final currency = ref.watch(currencyProvider);
    final colors = FinColors.of(context);
    final text = Theme.of(context).textTheme;
    final anyOver = alerts.any((s) => s.level == BudgetLevel.over);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: anyOver ? colors.expenseSoft : colors.warningSoft,
        borderRadius: BorderRadius.circular(FinRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(FinRadius.lg),
          onTap: () => context.go('/budgets'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Icon(
                    anyOver ? Symbols.error_rounded : Symbols.warning_rounded,
                    fill: 1,
                    size: 22,
                    color: anyOver ? colors.expense : colors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Budget alerts', style: text.title),
                    for (final s in alerts.take(3))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          s.level == BudgetLevel.over
                              ? '${s.category?.name ?? 'Category'} is over by ${formatMoney(-s.remaining, currency)}'
                              : '${s.category?.name ?? 'Category'}: ${(s.ratio * 100).round()}% used, '
                                  '${formatMoney(s.remaining, currency)} left',
                          style: text.body.tabular,
                        ),
                      ),
                  ]),
                ),
                Center(child: Icon(Symbols.chevron_right_rounded, color: colors.inkMuted)),
              ]),
            ),
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
    final colors = FinColors.of(context);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == accounts.length) {
            return SizedBox(
              width: 120,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(FinRadius.lg),
                  side: BorderSide(color: colors.lineStrong),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(FinRadius.lg),
                  onTap: () => context.push('/account'),
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Symbols.add_rounded, size: 20, color: colors.fin),
                    const SizedBox(height: 4),
                    Text('Add account', style: text.label.copyWith(color: colors.fin)),
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
                borderRadius: BorderRadius.circular(FinRadius.lg),
                onTap: () => context.push('/account', extra: a),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      IconBadge(icon: a.icon, color: a.color, size: 32),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.name, style: text.caption, overflow: TextOverflow.ellipsis)),
                    ]),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: MoneyText(a.balance, currency: currency, style: text.title),
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
    final colors = FinColors.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Savings goals',
          action: TextButton(onPressed: () => context.push('/goals'), child: const Text('See all'))),
      for (final g in goals)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              onTap: () => context.push('/goals'),
              leading: IconBadge(icon: g.icon, color: g.color),
              title: Text(g.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ProgressBar(
                  ratio: g.progress,
                  color: colors.categoryInk(Color(g.color)),
                  label: '${g.name} progress',
                ),
              ),
              trailing: Text('${formatMoney(g.savedAmount, currency, compact: true)} / '
                  '${formatMoney(g.targetAmount, currency, compact: true)}',
                  style: Theme.of(context).textTheme.label.tabular),
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
              icon: Symbols.receipt_long_rounded,
              title: 'No transactions yet',
              message: 'Add your first income or expense to get started.',
              action: FilledButton.icon(
                onPressed: () => context.push('/transaction'),
                icon: const Icon(Symbols.add_rounded),
                label: const Text('Add transaction'),
              ),
            )
          : Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: ListTile.divideTiles(
                context: context,
                tiles: [for (final tx in txs) TransactionTile(tx: tx, showDate: true)],
              ).toList()),
            ),
    );
  }
}
