import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'budget_logic.dart';

/// Budgets for a month joined with that month's spending.
final budgetStatusProvider = FutureProvider.family<List<BudgetStatus>, DateTime>((ref, month) async {
  // Subscribe to all three before awaiting so they load in parallel.
  final budgets = ref.watch(budgetsProvider(month).future);
  final totals = ref.watch(categoryTotalsProvider((from: month, to: month)).future);
  final categories = ref.watch(categoriesProvider.future);
  return combineBudgets(await budgets, await totals, {for (final c in await categories) c.id: c});
});

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  DateTime _month = monthStart(DateTime.now());

  Future<void> _copyPrevious() async {
    try {
      final copied = await ref.read(repositoryProvider).copyBudgetsFromPreviousMonth(_month);
      ref.invalidate(budgetsProvider);
      if (mounted) {
        showSnack(context, copied == 0 ? 'Nothing to copy from last month' : 'Copied $copied budget${copied == 1 ? '' : 's'}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ref.watch(budgetStatusProvider(_month));
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: "Copy last month's budgets",
            icon: const Icon(Symbols.content_copy_rounded),
            onPressed: _copyPrevious,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-budget',
        onPressed: () => showBudgetDialog(context, ref, month: _month),
        icon: const Icon(Symbols.add_rounded),
        label: const Text('Budget'),
      ),
      body: ContentWidth(
        child: Column(children: [
          MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
          Expanded(
            child: AsyncView(
              value: statuses,
              onRetry: () => ref.invalidate(budgetStatusProvider(_month)),
              builder: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Symbols.pie_chart_rounded,
                    title: 'No budgets for ${formatMonth(_month)}',
                    message: 'Set a monthly limit for a category and FinTrack will warn you before you overspend.',
                    action: OutlinedButton.icon(
                      onPressed: _copyPrevious,
                      icon: const Icon(Symbols.content_copy_rounded),
                      label: const Text("Copy last month's"),
                    ),
                  );
                }
                final totalLimit = list.fold<int>(0, (s, b) => s + b.budget.amount);
                final totalSpent = list.fold<int>(0, (s, b) => s + b.spent);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Total budgeted', style: Theme.of(context).textTheme.label),
                          const SizedBox(height: 4),
                          Text('${formatMoney(totalSpent, currency)} of ${formatMoney(totalLimit, currency)}',
                              style: Theme.of(context).textTheme.headline.tabular),
                          const SizedBox(height: 10),
                          BudgetProgressBar(
                            ratio: totalLimit == 0 ? 0 : totalSpent / totalLimit,
                            level: budgetLevel(spent: totalSpent, limit: totalLimit, threshold: 0.8),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final s in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _BudgetCard(status: s, month: _month),
                      ),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({super.key, required this.ratio, required this.level});

  final double ratio;
  final BudgetLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = FinColors.of(context);
    final color = switch (level) {
      BudgetLevel.ok => colors.fin,
      BudgetLevel.warning => colors.sun,
      BudgetLevel.over => colors.expense,
    };
    return ProgressBar(ratio: ratio, color: color, label: 'Budget used');
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.status, required this.month});

  final BudgetStatus status;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final c = status.category;
    final colors = FinColors.of(context);
    final text = Theme.of(context).textTheme;
    final remainingText = status.remaining >= 0
        ? '${formatMoney(status.remaining, currency)} left'
        : '${formatMoney(-status.remaining, currency)} over';
    // The level is never color alone: past the threshold the percentage gets
    // a warning icon, over the limit an error icon.
    final levelColor = switch (status.level) {
      BudgetLevel.ok => colors.ink,
      BudgetLevel.warning => colors.warning,
      BudgetLevel.over => colors.expense,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(FinRadius.lg),
        onTap: () => showBudgetDialog(context, ref, month: month, existing: status.budget),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBadge(icon: c?.icon ?? 'category', color: c?.color ?? 0xFF9CA3AF, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(c?.name ?? 'Category', style: text.title, overflow: TextOverflow.ellipsis)),
              if (status.level != BudgetLevel.ok)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    status.level == BudgetLevel.over ? Symbols.error_rounded : Symbols.warning_rounded,
                    fill: 1,
                    size: 18,
                    color: levelColor,
                    semanticLabel: status.level == BudgetLevel.over ? 'Over budget' : 'Near the limit',
                  ),
                ),
              Text('${(status.ratio * 100).round()}%', style: text.label.tabular.copyWith(color: levelColor)),
            ]),
            const SizedBox(height: 10),
            BudgetProgressBar(ratio: status.ratio, level: status.level),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text('${formatMoney(status.spent, currency)} of ${formatMoney(status.budget.amount, currency)}',
                    style: text.caption.tabular.copyWith(color: colors.inkMuted)),
              ),
              Text(
                remainingText,
                style: text.label.tabular.copyWith(color: status.remaining < 0 ? colors.expense : colors.ink),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

Future<void> showBudgetDialog(BuildContext context, WidgetRef ref, {required DateTime month, Budget? existing}) async {
  final categories = (await ref.read(categoriesProvider.future))
      .where((c) => c.kind == TxType.expense && (!c.isArchived || c.id == existing?.categoryId))
      .toList();
  final used = (await ref.read(budgetsProvider(month).future)).map((b) => b.categoryId).toSet();
  final available = categories.where((c) => c.id == existing?.categoryId || !used.contains(c.id)).toList();
  if (!context.mounted) return;
  if (available.isEmpty) {
    showSnack(context, 'Every expense category already has a budget this month.');
    return;
  }

  final currency = ref.read(currencyProvider);
  final amount = TextEditingController(
      text: existing == null ? '' : centsToDecimal(existing.amount).toStringAsFixed(2));
  var categoryId = existing?.categoryId ?? available.first.id;
  var threshold = existing?.alertThreshold ?? 0.8;
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(existing == null ? 'New budget · ${formatMonth(month)}' : 'Edit budget'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                icon: dropdownIcon,
                initialValue: categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in available) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: existing == null ? (v) => setState(() => categoryId = v!) : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 'Monthly limit', prefixText: '${currencySymbol(currency)} '),
                validator: (v) {
                  final cents = parseAmountInput(v ?? '');
                  return (cents == null || cents <= 0) ? 'Enter an amount greater than zero' : null;
                },
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Expanded(child: Text('Alert me at')),
                Text('${(threshold * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              Slider(
                value: threshold,
                min: 0.5,
                max: 1.0,
                divisions: 10,
                label: '${(threshold * 100).round()}%',
                onChanged: (v) => setState(() => threshold = v),
              ),
            ]),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(repositoryProvider).deleteBudget(existing.id!);
                  ref.invalidate(budgetsProvider);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) showError(dialogContext, e);
                }
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await ref.read(repositoryProvider).saveBudget(Budget(
                      id: existing?.id,
                      categoryId: categoryId,
                      month: month,
                      amount: parseAmountInput(amount.text)!,
                      alertThreshold: double.parse(threshold.toStringAsFixed(2)),
                    ));
                ref.invalidate(budgetsProvider);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) showError(dialogContext, e);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
