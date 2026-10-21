import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'recurrence.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-recurring',
        onPressed: () => context.push('/recurring/edit'),
        icon: const Icon(Symbols.add_rounded),
        label: const Text('New rule'),
      ),
      body: AsyncView(
        value: ref.watch(recurringRulesProvider),
        onRetry: () => ref.invalidate(recurringRulesProvider),
        builder: (rules) {
          if (rules.isEmpty) {
            return EmptyState(
              icon: Symbols.event_repeat_rounded,
              title: 'No recurring items',
              message: 'Add bills, subscriptions or your salary once and FinTrack records them on schedule.',
              action: FilledButton(
                  onPressed: () => context.push('/recurring/edit'), child: const Text('Add recurring item')),
            );
          }
          final active = rules.where((r) => r.isActive).toList();
          final paused = rules.where((r) => !r.isActive).toList();
          final monthlyNet = active.fold<int>(0, (s, r) => s + _monthlyEquivalent(r));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ContentWidth(
                maxWidth: 700,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (active.isNotEmpty)
                    Card(
                      child: ListTile(
                        title: const Text('Estimated per month'),
                        subtitle: Text('${active.length} active rule${active.length == 1 ? '' : 's'}'),
                        trailing: MoneyText(monthlyNet,
                            currency: currency, kind: AmountKind.net, style: Theme.of(context).textTheme.headline),
                      ),
                    ),
                  if (active.isNotEmpty) ...[
                    const SectionHeader('Active'),
                    Card(child: Column(children: [for (final r in active) _RuleTile(rule: r)])),
                  ],
                  if (paused.isNotEmpty) ...[
                    const SectionHeader('Paused or ended'),
                    Card(child: Column(children: [for (final r in paused) _RuleTile(rule: r)])),
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

/// Rough signed monthly amount for the summary card.
int _monthlyEquivalent(RecurringRule r) {
  final perMonth = switch (r.frequency) {
    Frequency.daily => r.amount * 365 / 12 / r.interval,
    Frequency.weekly => r.amount * 52 / 12 / r.interval,
    Frequency.monthly => r.amount / r.interval,
    Frequency.yearly => r.amount / 12 / r.interval,
  };
  return (r.type == TxType.income ? 1 : -1) * perMonth.round();
}

/// Whether a paused rule can run again (it has not passed its end date).
bool canResume(RecurringRule rule, {DateTime? now}) {
  if (rule.endDate == null) return true;
  final next = resumeDate(rule, now: now);
  return !next.isAfter(rule.endDate!);
}

/// Next run date when resuming: the first occurrence from today, so missed
/// periods while paused are skipped instead of being back-filled.
DateTime resumeDate(RecurringRule rule, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final from = rule.nextRunOn.isAfter(today) ? rule.nextRunOn : today;
  return firstOccurrenceOnOrAfter(from, rule.frequency, rule.interval, rule.startDate);
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.rule});

  final RecurringRule rule;

  Future<void> _setActive(BuildContext context, WidgetRef ref, bool active) async {
    final repo = ref.read(repositoryProvider);
    try {
      await repo.saveRecurringRule(RecurringRule(
        id: rule.id,
        accountId: rule.accountId,
        categoryId: rule.categoryId,
        type: rule.type,
        amount: rule.amount,
        note: rule.note,
        frequency: rule.frequency,
        interval: rule.interval,
        startDate: rule.startDate,
        nextRunOn: active ? resumeDate(rule) : rule.nextRunOn,
        endDate: rule.endDate,
        isActive: active,
      ));
      if (active) await repo.processDueRecurringRules();
      refreshFinanceData(ref);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final category = ref.watch(categoryMapProvider)[rule.categoryId];
    final account = ref.watch(accountMapProvider)[rule.accountId];
    final ended = !rule.isActive && !canResume(rule);
    final schedule = rule.frequency.describe(rule.interval);
    final String when;
    if (rule.isActive) {
      when = 'Next: ${formatRelativeDay(rule.nextRunOn)}';
    } else if (ended) {
      when = 'Ended ${formatDate(rule.endDate!)}';
    } else {
      when = 'Paused';
    }

    return ListTile(
      onTap: () => context.push('/recurring/edit', extra: rule),
      leading: IconBadge(icon: category?.icon ?? 'category', color: category?.color ?? 0xFF9CA3AF),
      title: Text(rule.note?.isNotEmpty == true ? rule.note! : (category?.name ?? 'Recurring')),
      subtitle: Text('$schedule · ${account?.name ?? 'Account'}\n$when'),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        MoneyText(
          rule.amount,
          currency: currency,
          kind: switch (rule.type) {
            TxType.income => AmountKind.income,
            TxType.expense => AmountKind.expense,
            TxType.transfer => AmountKind.plain,
          },
        ),
        const SizedBox(width: 4),
        Switch(
          value: rule.isActive,
          onChanged: ended ? null : (v) => _setActive(context, ref, v),
        ),
      ]),
    );
  }
}
