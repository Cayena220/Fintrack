import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-goal',
        onPressed: () => showGoalDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New goal'),
      ),
      body: AsyncView(
        value: ref.watch(goalsProvider),
        onRetry: () => ref.invalidate(goalsProvider),
        builder: (goals) {
          if (goals.isEmpty) {
            return EmptyState(
              icon: Icons.savings_outlined,
              title: 'No savings goals yet',
              message: 'Set a target, like an emergency fund or a new laptop, and track what you put aside.',
              action: FilledButton(onPressed: () => showGoalDialog(context, ref), child: const Text('Create a goal')),
            );
          }
          final active = goals.where((g) => !g.isCompleted).toList();
          final completed = goals.where((g) => g.isCompleted).toList();
          final saved = active.fold<int>(0, (s, g) => s + g.savedAmount);
          final target = active.fold<int>(0, (s, g) => s + g.targetAmount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ContentWidth(
                maxWidth: 700,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (active.isNotEmpty)
                    Card(
                      child: ListTile(
                        title: const Text('Saved across active goals'),
                        subtitle: Text('of ${formatMoney(target, currency)} total'),
                        trailing: Text(formatMoney(saved, currency),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  for (final g in active) ...[const SizedBox(height: 10), _GoalCard(goal: g)],
                  if (completed.isNotEmpty) ...[
                    const SectionHeader('Completed'),
                    for (final g in completed) ...[_GoalCard(goal: g), const SizedBox(height: 10)],
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

/// How much to save per month to hit [goal] by its target date, or null when
/// there is no date, the goal is reached, or the date has passed.
int? monthlySavingNeeded(SavingsGoal goal, {DateTime? now}) {
  final date = goal.targetDate;
  if (date == null || goal.remaining <= 0) return null;
  final today = dateOnly(now ?? DateTime.now());
  if (date.isBefore(today)) return null;
  // Count the current month, so a goal due this month needs everything now.
  final months = (date.year - today.year) * 12 + (date.month - today.month) + 1;
  return (goal.remaining / months).ceil();
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final theme = Theme.of(context);
    final perMonth = monthlySavingNeeded(goal);
    final overdue = !goal.isCompleted &&
        goal.remaining > 0 &&
        goal.targetDate != null &&
        goal.targetDate!.isBefore(dateOnly(DateTime.now()));

    final String detail;
    if (goal.isCompleted || goal.remaining == 0) {
      detail = 'Goal reached';
    } else if (overdue) {
      detail = 'Target date passed · ${formatMoney(goal.remaining, currency)} to go';
    } else if (perMonth != null) {
      detail = '${formatMoney(perMonth, currency)}/month until ${formatDate(goal.targetDate!)}';
    } else {
      detail = '${formatMoney(goal.remaining, currency)} to go';
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showGoalDetails(context, goal.id!),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBadge(icon: goal.icon, color: goal.color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(goal.name, style: theme.textTheme.titleSmall),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: overdue ? MoneyColors.warning(context) : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ]),
              ),
              Text('${(goal.progress * 100).round()}%', style: theme.textTheme.labelLarge),
            ]),
            const SizedBox(height: 10),
            GoalProgressBar(goal: goal),
            const SizedBox(height: 8),
            Text('${formatMoney(goal.savedAmount, currency)} of ${formatMoney(goal.targetAmount, currency)}',
                style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({super.key, required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) {
    final color = Color(goal.color);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: goal.progress,
        minHeight: 10,
        color: color,
        backgroundColor: color.withValues(alpha: 0.15),
        semanticsLabel: '${goal.name} progress',
        semanticsValue: '${(goal.progress * 100).round()}%',
      ),
    );
  }
}

/// Bottom sheet with a goal's progress, contribution history and actions.
/// Takes the id so the sheet re-reads the goal after each change.
Future<void> showGoalDetails(BuildContext context, String goalId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _GoalDetailsSheet(goalId: goalId),
  );
}

class _GoalDetailsSheet extends ConsumerWidget {
  const _GoalDetailsSheet({required this.goalId});

  final String goalId;

  Future<void> _toggleCompleted(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
    try {
      await ref.read(repositoryProvider).saveGoal(SavingsGoal(
            id: goal.id,
            name: goal.name,
            targetAmount: goal.targetAmount,
            targetDate: goal.targetDate,
            icon: goal.icon,
            color: goal.color,
            isCompleted: !goal.isCompleted,
            savedAmount: goal.savedAmount,
          ));
      ref.invalidate(goalsProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _deleteContribution(BuildContext context, WidgetRef ref, GoalContribution c) async {
    final ok = await confirmDialog(context, title: 'Delete this entry?', message: 'The goal total will be updated.');
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteContribution(c.id);
      ref.invalidate(goalsProvider);
      ref.invalidate(goalContributionsProvider(goalId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider).value ?? const <SavingsGoal>[];
    final goal = goals.where((g) => g.id == goalId).firstOrNull;
    if (goal == null) return const SizedBox(height: 120);

    final currency = ref.watch(currencyProvider);
    final theme = Theme.of(context);
    final contributions = ref.watch(goalContributionsProvider(goalId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(children: [
            IconBadge(icon: goal.icon, color: goal.color, size: 48),
            const SizedBox(width: 14),
            Expanded(child: Text(goal.name, style: theme.textTheme.titleLarge)),
            IconButton(
              tooltip: 'Edit goal',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showGoalDialog(context, ref, existing: goal),
            ),
          ]),
          const SizedBox(height: 16),
          Text(formatMoney(goal.savedAmount, currency),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text('saved of ${formatMoney(goal.targetAmount, currency)}'
              '${goal.targetDate == null ? '' : ' · target ${formatDate(goal.targetDate!)}'}'),
          const SizedBox(height: 12),
          GoalProgressBar(goal: goal),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => showContributionDialog(context, ref, goal: goal),
                icon: const Icon(Icons.add),
                label: const Text('Add money'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: goal.savedAmount > 0
                    ? () => showContributionDialog(context, ref, goal: goal, withdraw: true)
                    : null,
                icon: const Icon(Icons.remove),
                label: const Text('Withdraw'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mark as completed'),
            value: goal.isCompleted,
            onChanged: (_) => _toggleCompleted(context, ref, goal),
          ),
          const SectionHeader('History'),
          AsyncView(
            value: contributions,
            onRetry: () => ref.invalidate(goalContributionsProvider(goalId)),
            builder: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Nothing added yet.', textAlign: TextAlign.center),
                );
              }
              return Column(children: [
                for (final c in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(c.amount >= 0 ? Icons.south_west : Icons.north_east),
                    title: Text(c.note ?? (c.amount >= 0 ? 'Added' : 'Withdrawn')),
                    subtitle: Text(formatRelativeDay(c.contributedOn)),
                    trailing: MoneyText(c.amount, currency: currency),
                    onLongPress: () => _deleteContribution(context, ref, c),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Long-press an entry to delete it.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

Future<void> showGoalDialog(BuildContext context, WidgetRef ref, {SavingsGoal? existing}) async {
  final currency = ref.read(currencyProvider);
  final name = TextEditingController(text: existing?.name ?? '');
  final target = TextEditingController(
      text: existing == null ? '' : centsToDecimal(existing.targetAmount).toStringAsFixed(2));
  var targetDate = existing?.targetDate;
  var color = existing?.color ?? 0xFF0EA5E9;
  var icon = existing?.icon ?? 'savings';
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(existing == null ? 'New savings goal' : 'Edit goal'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: name,
                  autofocus: existing == null,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Goal name', hintText: 'e.g. Emergency fund'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(labelText: 'Target amount', prefixText: '${currencySymbol(currency)} '),
                  validator: (v) {
                    final cents = parseAmountInput(v ?? '');
                    if (cents == null || cents <= 0) return 'Enter an amount greater than zero';
                    if (cents >= 100000000000000) return 'That amount is too large';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Target date (optional)'),
                  subtitle: Text(targetDate == null ? 'No deadline' : formatDate(targetDate!)),
                  trailing: targetDate == null
                      ? const Icon(Icons.edit_calendar_outlined)
                      : IconButton(
                          tooltip: 'Clear date',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => targetDate = null),
                        ),
                  onTap: () async {
                    final today = dateOnly(DateTime.now());
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: targetDate ?? DateTime(today.year + 1, today.month, today.day),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(today.year + 50),
                    );
                    if (picked != null) setState(() => targetDate = picked);
                  },
                ),
                const SizedBox(height: 12),
                Text('Color', style: Theme.of(dialogContext).textTheme.titleSmall),
                const SizedBox(height: 8),
                ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
                const SizedBox(height: 16),
                Text('Icon', style: Theme.of(dialogContext).textTheme.titleSmall),
                const SizedBox(height: 8),
                IconPickerGrid(selected: icon, color: color, onChanged: (i) => setState(() => icon = i)),
              ]),
            ),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(dialogContext,
                    title: 'Delete ${existing.name}?', message: 'Its contribution history will be deleted too.');
                if (!ok) return;
                try {
                  await ref.read(repositoryProvider).deleteGoal(existing.id!);
                  ref.invalidate(goalsProvider);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  // Also close the details sheet that opened this dialog.
                  if (context.mounted) Navigator.of(context).maybePop();
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
                await ref.read(repositoryProvider).saveGoal(SavingsGoal(
                      id: existing?.id,
                      name: name.text.trim(),
                      targetAmount: parseAmountInput(target.text)!,
                      targetDate: targetDate,
                      icon: icon,
                      color: color,
                      isCompleted: existing?.isCompleted ?? false,
                      savedAmount: existing?.savedAmount ?? 0,
                    ));
                ref.invalidate(goalsProvider);
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

/// Adds money to a goal, or takes it out when [withdraw] is true (stored as
/// a negative contribution).
Future<void> showContributionDialog(BuildContext context, WidgetRef ref,
    {required SavingsGoal goal, bool withdraw = false}) async {
  final currency = ref.read(currencyProvider);
  final amount = TextEditingController();
  final note = TextEditingController();
  var date = dateOnly(DateTime.now());
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(withdraw ? 'Withdraw from ${goal.name}' : 'Add to ${goal.name}'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${currencySymbol(currency)} ',
                  helperText: withdraw
                      ? 'Up to ${formatMoney(goal.savedAmount, currency)}'
                      : (goal.remaining > 0 ? '${formatMoney(goal.remaining, currency)} to reach the goal' : null),
                ),
                validator: (v) {
                  final cents = parseAmountInput(v ?? '');
                  if (cents == null || cents <= 0) return 'Enter an amount greater than zero';
                  if (withdraw && cents > goal.savedAmount) return 'You only have ${formatMoney(goal.savedAmount, currency)} saved';
                  if (cents >= 100000000000000) return 'That amount is too large';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Date'),
                subtitle: Text(formatRelativeDay(date)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => date = picked);
                },
              ),
              TextFormField(
                controller: note,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final cents = parseAmountInput(amount.text)!;
              try {
                await ref.read(repositoryProvider).addContribution(
                      goalId: goal.id!,
                      amount: withdraw ? -cents : cents,
                      date: date,
                      note: note.text,
                    );
                ref.invalidate(goalsProvider);
                ref.invalidate(goalContributionsProvider(goal.id!));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (!withdraw && goal.savedAmount < goal.targetAmount && goal.savedAmount + cents >= goal.targetAmount) {
                  if (context.mounted) showSnack(context, 'You reached your ${goal.name} goal!');
                }
              } catch (e) {
                if (dialogContext.mounted) showError(dialogContext, e);
              }
            },
            child: Text(withdraw ? 'Withdraw' : 'Add'),
          ),
        ],
      ),
    ),
  );
}
