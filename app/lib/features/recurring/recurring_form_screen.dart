import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'recurrence.dart';

/// Next run date for a saved rule. A new rule starts at its start date, so a
/// past start date back-fills the missed occurrences. When an existing rule's
/// schedule changes, the next run moves to the new schedule's first date from
/// today, skipping today if the old schedule may already have posted it.
DateTime scheduleNextRun({
  required RecurringRule? existing,
  required Frequency frequency,
  required int interval,
  required DateTime startDate,
  DateTime? now,
}) {
  if (existing == null) return startDate;
  final unchanged = existing.frequency == frequency &&
      existing.interval == interval &&
      existing.startDate == startDate;
  if (unchanged) return existing.nextRunOn;

  final today = dateOnly(now ?? DateTime.now());
  final mayHavePostedToday = existing.nextRunOn.isAfter(today);
  var from = mayHavePostedToday ? today.add(const Duration(days: 1)) : today;
  if (startDate.isAfter(from)) from = startDate;
  return firstOccurrenceOnOrAfter(from, frequency, interval, startDate);
}

class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.existing});

  final RecurringRule? existing;

  @override
  ConsumerState<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  final _form = GlobalKey<FormState>();
  late TxType _type;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _interval;
  String? _accountId;
  String? _categoryId;
  late Frequency _frequency;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? TxType.expense;
    _amount = TextEditingController(text: e == null ? '' : centsToDecimal(e.amount).toStringAsFixed(2));
    _note = TextEditingController(text: e?.note ?? '');
    _interval = TextEditingController(text: '${e?.interval ?? 1}');
    _accountId = e?.accountId;
    _categoryId = e?.categoryId;
    _frequency = e?.frequency ?? Frequency.monthly;
    _startDate = e?.startDate ?? dateOnly(DateTime.now());
    _endDate = e?.endDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  int get _intervalValue => int.tryParse(_interval.text) ?? 1;

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime(_startDate.year + 1, _startDate.month, _startDate.day),
      firstDate: _startDate,
      lastDate: DateTime(_startDate.year + 50),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      showSnack(context, 'Pick a category');
      return;
    }
    final nextRun = scheduleNextRun(
      existing: widget.existing,
      frequency: _frequency,
      interval: _intervalValue,
      startDate: _startDate,
    );
    final ended = _endDate != null && nextRun.isAfter(_endDate!);

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    try {
      await repo.saveRecurringRule(RecurringRule(
        id: widget.existing?.id,
        accountId: _accountId!,
        categoryId: _categoryId!,
        type: _type,
        amount: parseAmountInput(_amount.text)!,
        note: _note.text,
        frequency: _frequency,
        interval: _intervalValue,
        startDate: _startDate,
        nextRunOn: nextRun,
        endDate: _endDate,
        isActive: (widget.existing?.isActive ?? true) && !ended,
      ));
      // Post anything already due (e.g. a rule starting today) right away.
      final posted = await repo.processDueRecurringRules();
      refreshFinanceData(ref);
      if (mounted) {
        if (posted > 0) showSnack(context, 'Recorded $posted transaction${posted == 1 ? '' : 's'}');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this recurring item?',
      message: 'Transactions it already recorded are kept.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteRecurringRule(widget.existing!.id!);
      refreshFinanceData(ref);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    final currency = ref.watch(currencyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit recurring item' : 'New recurring item'),
        actions: [
          if (_isEdit) IconButton(tooltip: 'Delete', icon: const Icon(Symbols.delete_rounded), onPressed: _delete),
        ],
      ),
      body: AsyncView(
        value: accounts,
        builder: (accountList) {
          final active = accountList.where((a) => !a.isArchived || a.id == _accountId).toList();
          if (active.isEmpty) {
            return EmptyState(
              icon: Symbols.account_balance_wallet_rounded,
              title: 'Add an account first',
              action: FilledButton(onPressed: () => context.push('/account'), child: const Text('Add account')),
            );
          }
          _accountId ??= active.first.id;
          final kindCategories = (categories.value ?? const <Category>[])
              .where((c) => c.kind == _type && (!c.isArchived || c.id == _categoryId))
              .toList();

          final nextRun = scheduleNextRun(
            existing: widget.existing,
            frequency: _frequency,
            interval: _intervalValue.clamp(1, 365),
            startDate: _startDate,
          );
          final upcoming = upcomingOccurrences(nextRun, _frequency, _intervalValue.clamp(1, 365), _startDate,
              endDate: _endDate);
          final backfill = !_isEdit && _startDate.isBefore(dateOnly(DateTime.now()));

          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ContentWidth(
                maxWidth: 600,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SegmentedButton<TxType>(
                    segments: const [
                      ButtonSegment(value: TxType.expense, label: Text('Expense'), icon: Icon(Symbols.north_east_rounded)),
                      ButtonSegment(value: TxType.income, label: Text('Income'), icon: Icon(Symbols.south_west_rounded)),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _categoryId = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _amount,
                    autofocus: !_isEdit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    style: theme.textTheme.headline.tabular,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '${currencySymbol(currency)} ',
                      prefixStyle: theme.textTheme.headline.copyWith(color: FinColors.of(context).inkMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                    ),
                    validator: (v) {
                      final cents = parseAmountInput(v ?? '');
                      if (cents == null || cents <= 0) return 'Enter an amount greater than zero';
                      if (cents >= 100000000000000) return 'That amount is too large';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _note,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Name (optional)',
                      hintText: 'e.g. Netflix, Rent, Salary',
                      prefixIcon: Icon(Symbols.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    icon: dropdownIcon,
                    initialValue: _accountId,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: [for (final a in active) DropdownMenuItem(value: a.id, child: Text(a.name))],
                    onChanged: (v) => setState(() => _accountId = v),
                  ),
                  const SizedBox(height: 20),
                  Text('Category', style: theme.textTheme.label),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in kindCategories)
                      ChoiceChip(
                        avatar: IconBadge(icon: c.icon, color: c.color, size: 24, round: true),
                        label: Text(c.name),
                        selected: _categoryId == c.id,
                        onSelected: (_) => setState(() => _categoryId = c.id),
                      ),
                  ]),
                  const SizedBox(height: 24),
                  Text('Schedule', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: _interval,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Every'),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return (n == null || n < 1 || n > 365) ? '1–365' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<Frequency>(
                        icon: dropdownIcon,
                        initialValue: _frequency,
                        decoration: const InputDecoration(labelText: 'Period'),
                        items: [
                          for (final f in Frequency.values)
                            DropdownMenuItem(value: f, child: Text(f.unit(_intervalValue))),
                        ],
                        onChanged: (f) => setState(() => _frequency = f!),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Symbols.event_rounded),
                    title: const Text('Starts'),
                    subtitle: Text(formatRelativeDay(_startDate)),
                    trailing: const Icon(Symbols.edit_calendar_rounded),
                    onTap: _pickStart,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Symbols.event_busy_rounded),
                    title: const Text('Ends'),
                    subtitle: Text(_endDate == null ? 'Never' : formatDate(_endDate!)),
                    trailing: _endDate == null
                        ? const Icon(Symbols.edit_calendar_rounded)
                        : IconButton(
                            tooltip: 'Remove end date',
                            icon: const Icon(Symbols.clear_rounded),
                            onPressed: () => setState(() => _endDate = null),
                          ),
                    onTap: _pickEnd,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Next dates', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        if (upcoming.isEmpty)
                          const Text('No more dates before the end date.')
                        else
                          for (final d in upcoming) Text(formatRelativeDay(d)),
                        if (backfill) ...[
                          const SizedBox(height: 8),
                          Text(
                            'The start date is in the past, so dates since then will be recorded when you save.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isEdit ? 'Save changes' : 'Create'),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}
