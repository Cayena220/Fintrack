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
import '../budgets/budget_alerts.dart';

/// Add or edit an income, expense or transfer.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.existing, this.initialType});

  final Transaction? existing;
  final TxType? initialType;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _form = GlobalKey<FormState>();
  late TxType _type;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  late DateTime _date;
  bool _saving = false;

  bool get _isEdit => widget.existing?.id != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? widget.initialType ?? TxType.expense;
    _amount = TextEditingController(text: e == null ? '' : centsToDecimal(e.amount).toStringAsFixed(2));
    _note = TextEditingController(text: e?.note ?? '');
    _accountId = e?.accountId;
    _toAccountId = e?.toAccountId;
    _categoryId = e?.categoryId;
    _date = e?.occurredOn ?? dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_type != TxType.transfer && _categoryId == null) {
      showSnack(context, 'Pick a category');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final synced = await repo.saveTransaction(Transaction(
        id: widget.existing?.id,
        accountId: _accountId!,
        categoryId: _type == TxType.transfer ? null : _categoryId,
        type: _type,
        amount: parseAmountInput(_amount.text)!,
        occurredOn: _date,
        note: _note.text,
        toAccountId: _type == TxType.transfer ? _toAccountId : null,
        recurringRuleId: widget.existing?.recurringRuleId,
      ), original: widget.existing);
      refreshFinanceData(ref);
      if (!synced) {
        messenger.showSnackBar(const SnackBar(content: Text("Saved on this device. It will sync when you're back online."), behavior: SnackBarBehavior.floating));
      }
      if (_type == TxType.expense) {
        // Fire-and-forget: alerts must not delay closing the form.
        checkBudgetAlerts(repo, ref.read(currencyProvider)).ignore();
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Delete transaction?', message: 'This cannot be undone.');
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteTransaction(widget.existing!);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'New transaction'),
        actions: [
          if (_isEdit) IconButton(tooltip: 'Delete', icon: const Icon(Symbols.delete_rounded), onPressed: _delete),
        ],
      ),
      body: AsyncView(
        value: accounts,
        builder: (accountList) {
          final active = accountList.where((a) => !a.isArchived || a.id == _accountId || a.id == _toAccountId).toList();
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

          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ContentWidth(
                  maxWidth: 600,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SegmentedButton<TxType>(
                      // No checkmark and scale-down labels so the words stay on one line on narrow phones.
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
                      ),
                      segments: const [
                        ButtonSegment(value: TxType.expense, label: _SegmentLabel('Expense'), icon: Icon(Symbols.north_east_rounded)),
                        ButtonSegment(value: TxType.income, label: _SegmentLabel('Income'), icon: Icon(Symbols.south_west_rounded)),
                        ButtonSegment(value: TxType.transfer, label: _SegmentLabel('Transfer'), icon: Icon(Symbols.swap_horiz_rounded)),
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
                      // The amount field: display face, tabular figures, the symbol as a muted prefix.
                      style: Theme.of(context).textTheme.headline.tabular,
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: '${currencySymbol(currency)} ',
                        prefixStyle: Theme.of(context).textTheme.headline.copyWith(color: FinColors.of(context).inkMuted),
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
                    DropdownButtonFormField<String>(
                      icon: dropdownIcon,
                      initialValue: _accountId,
                      decoration: InputDecoration(labelText: _type == TxType.transfer ? 'From account' : 'Account'),
                      items: [for (final a in active) DropdownMenuItem(value: a.id, child: Text(a.name))],
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
                    if (_type == TxType.transfer) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        icon: dropdownIcon,
                        initialValue: _toAccountId,
                        decoration: const InputDecoration(labelText: 'To account'),
                        items: [
                          for (final a in active.where((a) => a.id != _accountId))
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                        ],
                        validator: (v) => v == null
                            ? 'Choose where the money goes'
                            : (v == _accountId ? 'Choose a different account' : null),
                        onChanged: (v) => setState(() => _toAccountId = v),
                      ),
                    ] else ...[
                      const SizedBox(height: 20),
                      Text('Category', style: Theme.of(context).textTheme.label),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final c in kindCategories)
                          ChoiceChip(
                            avatar: IconBadge(icon: c.icon, color: c.color, size: 24, round: true),
                            label: Text(c.name),
                            selected: _categoryId == c.id,
                            onSelected: (_) => setState(() => _categoryId = c.id),
                          ),
                        ActionChip(
                          avatar: const Icon(Symbols.add_rounded, size: 18),
                          label: Text('New', style: TextStyle(color: FinColors.of(context).fin)),
                          onPressed: () => context.push('/categories'),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.event_rounded),
                      title: const Text('Date'),
                      subtitle: Text(formatRelativeDay(_date)),
                      trailing: const Icon(Symbols.edit_calendar_rounded),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _note,
                      maxLength: 500,
                      maxLines: 2,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Note (optional)', prefixIcon: Icon(Symbols.notes_rounded)),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isEdit ? 'Save changes' : 'Add transaction'),
                    ),
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));
  }
}
