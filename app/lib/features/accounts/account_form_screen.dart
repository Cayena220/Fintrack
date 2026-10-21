import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.existing});

  final Account? existing;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _initial;
  late AccountType _type;
  late int _color;
  late String _icon;
  late bool _archived;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _initial = TextEditingController(text: e == null ? '0.00' : centsToDecimal(e.initialBalance).toStringAsFixed(2));
    _type = e?.type ?? AccountType.bank;
    _color = e?.color ?? 0xFF059669;
    _icon = e?.icon ?? _type.defaultIcon;
    _archived = e?.isArchived ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveAccount(Account(
            id: widget.existing?.id ?? '',
            name: _name.text.trim(),
            type: _type,
            initialBalance: parseAmountInput(_initial.text) ?? 0,
            balance: 0,
            color: _color,
            icon: _icon,
            isArchived: _archived,
          ));
      refreshFinanceData(ref);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${widget.existing!.name}?',
      message: 'All transactions in this account will be deleted too. '
          'To keep your history, archive the account instead.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteAccount(widget.existing!.id);
      refreshFinanceData(ref);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit account' : 'New account'),
        actions: [
          if (_isEdit) IconButton(tooltip: 'Delete', icon: const Icon(Symbols.delete_rounded), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ContentWidth(
            maxWidth: 600,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: IconBadge(icon: _icon, color: _color, size: 64)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Account name', hintText: 'e.g. BDO Savings, GCash'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AccountType>(
                icon: dropdownIcon,
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [for (final t in AccountType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: (t) => setState(() {
                  if (_icon == _type.defaultIcon) _icon = t!.defaultIcon;
                  _type = t!;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _initial,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
                decoration: InputDecoration(
                  labelText: 'Starting balance',
                  prefixText: '${currencySymbol(currency)} ',
                  helperText: _type == AccountType.credit
                      ? 'Use a negative number for an existing card balance you owe.'
                      : 'The balance before the first transaction you record here.',
                ),
                validator: (v) => parseAmountInput(v ?? '') == null ? 'Enter a number' : null,
              ),
              const SizedBox(height: 20),
              Text('Color', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
              const SizedBox(height: 20),
              Text('Icon', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              IconPickerGrid(selected: _icon, color: _color, onChanged: (i) => setState(() => _icon = i)),
              if (_isEdit) ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Archived'),
                  subtitle: const Text('Hidden from pickers and totals; history is kept.'),
                  value: _archived,
                  onChanged: (v) => setState(() => _archived = v),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_isEdit ? 'Save changes' : 'Create account')),
            ]),
          ),
        ]),
      ),
    );
  }
}
