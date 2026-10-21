import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/account'),
        icon: const Icon(Symbols.add_rounded),
        label: const Text('Add account'),
      ),
      body: AsyncView(
        value: ref.watch(accountsProvider),
        onRetry: () => ref.invalidate(accountsProvider),
        builder: (accounts) {
          final active = accounts.where((a) => !a.isArchived).toList();
          final archived = accounts.where((a) => a.isArchived).toList();
          final total = active.fold<int>(0, (s, a) => s + a.balance);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ContentWidth(
                maxWidth: 700,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Card(
                    child: ListTile(
                      title: const Text('Net worth'),
                      subtitle: Text('${active.length} active account${active.length == 1 ? '' : 's'}'),
                      trailing: MoneyText(total, currency: currency, style: Theme.of(context).textTheme.headline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(child: Column(children: [for (final a in active) _AccountTile(account: a)])),
                  if (archived.isNotEmpty) ...[
                    const SectionHeader('Archived'),
                    Card(child: Column(children: [for (final a in archived) _AccountTile(account: a)])),
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

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      onTap: () => context.push('/account', extra: account),
      leading: IconBadge(icon: account.icon, color: account.color),
      title: Text(account.name),
      subtitle: Text(account.type.label),
      trailing: MoneyText(account.balance, currency: ref.watch(currencyProvider)),
    );
  }
}
