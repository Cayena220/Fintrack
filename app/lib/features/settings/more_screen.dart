import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../data/providers.dart';

const _items = [
  (icon: Icons.account_balance_wallet_outlined, title: 'Accounts', subtitle: 'Cash, banks, e-wallets, cards', path: '/accounts'),
  (icon: Icons.savings_outlined, title: 'Savings goals', subtitle: 'Targets and contributions', path: '/goals'),
  (icon: Icons.event_repeat_outlined, title: 'Recurring', subtitle: 'Bills, subscriptions and salary', path: '/recurring'),
  (icon: Icons.category_outlined, title: 'Categories', subtitle: 'Add or archive categories', path: '/categories'),
  (icon: Icons.settings_outlined, title: 'Settings', subtitle: 'Profile, currency, theme, sign out', path: '/settings'),
];

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final email = ref.watch(supabaseProvider).auth.currentUser?.email;
    final theme = Theme.of(context);
    final name = profile?.displayName?.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ContentWidth(
            maxWidth: 700,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                child: ListTile(
                  onTap: () => context.push('/settings'),
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: Text(_initial(name, email)),
                  ),
                  title: Text(name?.isNotEmpty == true ? name! : 'Your profile'),
                  subtitle: email == null ? null : Text(email),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  for (final item in _items)
                    ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.title),
                      subtitle: Text(item.subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(item.path),
                    ),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

String _initial(String? name, String? email) {
  final source = (name?.isNotEmpty == true ? name : email) ?? '?';
  return source.characters.first.toUpperCase();
}
