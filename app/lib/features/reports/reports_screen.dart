import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'csv_export.dart';

enum ReportPeriod {
  thisMonth('This month', 1),
  last3('Last 3 months', 3),
  last6('Last 6 months', 6),
  last12('Last 12 months', 12);

  const ReportPeriod(this.label, this.months);
  final String label;
  final int months;

  MonthRange range(DateTime now) {
    final to = monthStart(now);
    return (from: addMonths(to, -(months - 1)), to: to);
  }
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _exporting = false;

  Future<void> _export(MonthRange range) async {
    setState(() => _exporting = true);
    try {
      final path = await exportTransactionsCsv(
        ref.read(repositoryProvider),
        from: range.from,
        to: addMonths(range.to, 1).subtract(const Duration(days: 1)),
        accounts: ref.read(accountMapProvider),
        categories: ref.read(categoryMapProvider),
      );
      if (mounted && path != null) showSnack(context, 'Exported to $path');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _period.range(DateTime.now());
    final totals = ref.watch(categoryTotalsProvider(range));
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exporting ? null : () => _export(range),
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: AsyncView(
        value: totals,
        onRetry: () => ref.invalidate(categoryTotalsProvider(range)),
        builder: (rows) {
          final income = rows.where((r) => r.type == TxType.income).fold<int>(0, (s, r) => s + r.total);
          final expense = rows.where((r) => r.type == TxType.expense).fold<int>(0, (s, r) => s + r.total);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              ContentWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final p in ReportPeriod.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(p.label),
                            selected: _period == p,
                            onSelected: (_) => setState(() => _period = p),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _StatCard(label: 'Income', cents: income, currency: currency, color: MoneyColors.income(context))),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(label: 'Expenses', cents: expense, currency: currency, color: MoneyColors.expense(context))),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(label: 'Saved', cents: income - expense, currency: currency)),
                  ]),
                  if (rows.isEmpty)
                    const EmptyState(
                      icon: Icons.insights_outlined,
                      title: 'No data for this period',
                      message: 'Charts appear once you record income and expenses.',
                    )
                  else ...[
                    const SectionHeader('Spending by category'),
                    _CategoryBreakdown(rows: rows.where((r) => r.type == TxType.expense).toList(), currency: currency),
                    if (_period != ReportPeriod.thisMonth) ...[
                      const SectionHeader('Income vs. expenses'),
                      _MonthlyBars(rows: rows, range: range, currency: currency),
                    ],
                  ],
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.cents, required this.currency, this.color});

  final String label;
  final int cents;
  final String currency;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(formatMoney(cents, currency),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

/// Donut chart plus a ranked list of categories.
class _CategoryBreakdown extends StatefulWidget {
  const _CategoryBreakdown({required this.rows, required this.currency});

  final List<CategoryTotal> rows;
  final String currency;

  @override
  State<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<_CategoryBreakdown> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    // Merge months into one total per category.
    final byCategory = <String, ({String name, int color, String icon, int total})>{};
    for (final r in widget.rows) {
      final prev = byCategory[r.categoryId];
      byCategory[r.categoryId] = (
        name: r.categoryName,
        color: r.categoryColor,
        icon: r.categoryIcon,
        total: (prev?.total ?? 0) + r.total,
      );
    }
    final items = byCategory.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    final sum = items.fold<int>(0, (s, i) => s + i.total);
    if (sum == 0) {
      return const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No expenses in this period.')));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(
            height: 220,
            child: Stack(alignment: Alignment.center, children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 62,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        _touched = event.isInterestedForInteractions
                            ? response?.touchedSection?.touchedSectionIndex
                            : null;
                      });
                    },
                  ),
                  sections: [
                    for (var i = 0; i < items.length; i++)
                      PieChartSectionData(
                        value: items[i].total.toDouble(),
                        color: Color(items[i].color),
                        radius: _touched == i ? 40 : 32,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _touched != null && _touched! >= 0 && _touched! < items.length ? items[_touched!].name : 'Total',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  formatMoney(
                      _touched != null && _touched! >= 0 && _touched! < items.length ? items[_touched!].total : sum,
                      widget.currency),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: IconBadge(icon: item.icon, color: item.color, size: 32),
              title: Text(item.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: item.total / sum, minHeight: 5, color: Color(item.color)),
                ),
              ),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatMoney(item.total, widget.currency), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${(item.total * 100 / sum).toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Grouped bars: income and expenses per month.
class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.rows, required this.range, required this.currency});

  final List<CategoryTotal> rows;
  final MonthRange range;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final months = <DateTime>[];
    for (var m = range.from; !m.isAfter(range.to); m = addMonths(m, 1)) {
      months.add(m);
    }
    int sumFor(DateTime m, TxType type) =>
        rows.where((r) => r.month == m && r.type == type).fold<int>(0, (s, r) => s + r.total);

    final incomeColor = MoneyColors.income(context);
    final expenseColor = MoneyColors.expense(context);
    var maxY = 0.0;
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < months.length; i++) {
      final inc = sumFor(months[i], TxType.income) / 100;
      final exp = sumFor(months[i], TxType.expense) / 100;
      if (inc > maxY) maxY = inc;
      if (exp > maxY) maxY = exp;
      groups.add(BarChartGroupData(x: i, barsSpace: 3, barRods: [
        BarChartRodData(toY: inc, color: incomeColor, width: months.length > 6 ? 6 : 12, borderRadius: BorderRadius.circular(3)),
        BarChartRodData(toY: exp, color: expenseColor, width: months.length > 6 ? 6 : 12, borderRadius: BorderRadius.circular(3)),
      ]));
    }
    final labelStyle = Theme.of(context).textTheme.labelSmall;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
        child: Column(children: [
          SizedBox(
            height: 220,
            child: BarChart(BarChartData(
              maxY: maxY == 0 ? 1 : maxY * 1.15,
              barGroups: groups,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    '${rodIndex == 0 ? 'Income' : 'Expenses'}\n${formatMoney((rod.toY * 100).round(), currency)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (value, meta) => value == meta.max
                        ? const SizedBox.shrink()
                        : Text(formatMoney((value * 100).round(), currency, compact: true), style: labelStyle),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(formatShortMonth(months[i]), style: labelStyle),
                      );
                    },
                  ),
                ),
              ),
            )),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Legend(color: incomeColor, label: 'Income'),
            const SizedBox(width: 16),
            _Legend(color: expenseColor, label: 'Expenses'),
          ]),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ]);
  }
}
