import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'transaction_tile.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  DateTime _month = monthStart(DateTime.now());
  TxType? _type;
  String? _accountId;
  String? _categoryId;
  String _search = '';
  final _searchController = TextEditingController();

  TxFilter get _filter =>
      (month: _month, type: _type, accountId: _accountId, categoryId: _categoryId, search: _search);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _delete(Transaction tx) async {
    final ok = await confirmDialog(context, title: 'Delete transaction?', message: 'This cannot be undone.');
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteTransaction(tx.id!);
      refreshFinanceData(ref);
      if (mounted) showSnack(context, 'Transaction deleted');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openFilters() async {
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Filter', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All accounts')),
                for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All categories')),
                for (final c in categories) DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.kind.label})')),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _accountId = null;
                      _categoryId = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(transactionsProvider(_filter));
    final currency = ref.watch(currencyProvider);
    final hasExtraFilters = _accountId != null || _categoryId != null;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: _openFilters,
            icon: Badge(isLabelVisible: hasExtraFilters, child: const Icon(Icons.filter_list)),
          ),
        ],
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton(
              tooltip: 'New transaction',
              onPressed: () => context.push('/transaction'),
              child: const Icon(Icons.add),
            ),
      body: ContentWidth(
        child: Column(children: [
          MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
              ),
              onSubmitted: (v) => setState(() => _search = v.trim()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(children: [
              for (final t in <TxType?>[null, TxType.expense, TxType.income, TxType.transfer])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t?.label ?? 'All'),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(transactionsProvider(_filter));
                await ref.read(transactionsProvider(_filter).future);
              },
              child: AsyncView(
                value: txs,
                onRetry: () => ref.invalidate(transactionsProvider(_filter)),
                builder: (list) {
                  if (list.isEmpty) {
                    return ListView(children: const [
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Nothing here',
                        message: 'No transactions match this month and filter.',
                      ),
                    ]);
                  }
                  final income = list.where((t) => t.type == TxType.income).fold<int>(0, (s, t) => s + t.amount);
                  final expense = list.where((t) => t.type == TxType.expense).fold<int>(0, (s, t) => s + t.amount);

                  // Group by day, newest first.
                  final groups = <DateTime, List<Transaction>>{};
                  for (final tx in list) {
                    groups.putIfAbsent(tx.occurredOn, () => []).add(tx);
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                            _Total(label: 'Income', child: MoneyText(income, currency: currency, signed: false)),
                            _Total(label: 'Expenses', child: MoneyText(-expense, currency: currency, signed: false)),
                            _Total(label: 'Net', child: MoneyText(income - expense, currency: currency)),
                          ]),
                        ),
                      ),
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                          child: Text(formatRelativeDay(entry.key),
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )),
                        ),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(children: [
                            for (final tx in entry.value)
                              Dismissible(
                                key: ValueKey(tx.id),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) async {
                                  await _delete(tx);
                                  return false; // the list reloads itself after a delete
                                },
                                background: Container(
                                  color: Theme.of(context).colorScheme.errorContainer,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                                ),
                                child: TransactionTile(tx: tx),
                              ),
                          ]),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      child,
    ]);
  }
}
