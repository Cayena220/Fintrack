import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/formatters.dart';
import '../../core/settings.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';
import '../../services/update_service.dart';
import '../auth/google_auth.dart';

/// Currencies offered in Settings. Amounts are not converted when the
/// currency changes; only how they are displayed.
const supportedCurrencies = [
  'PHP', 'USD', 'EUR', 'GBP', 'JPY', 'SGD', 'AUD', 'CAD', 'NZD', 'HKD', 'CNY', 'KRW',
  'INR', 'MYR', 'IDR', 'THB', 'VND', 'AED', 'SAR', 'CHF',
];

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checkingUpdate = false;

  Future<void> _editName(String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await _updateProfile(displayName: name.trim());
  }

  Future<void> _updateProfile({String? displayName, String? currency}) async {
    try {
      await ref.read(repositoryProvider).updateProfile(displayName: displayName, currency: currency);
      ref.invalidate(profileProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final update = await findAvailableUpdate(ref.read(repositoryProvider));
      if (!mounted) return;
      if (update == null) {
        showSnack(context, 'You have the latest version.');
      } else {
        await showUpdateDialog(context, update);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message: 'Your data stays saved in your account.',
      confirmLabel: 'Sign out',
      destructive: false,
    );
    if (!ok) return;
    try {
      // The router redirects to the sign-in page on the auth change.
      await signOutEverywhere(ref.read(supabaseProvider));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final themeMode = ref.watch(themeModeProvider);
    final email = ref.watch(supabaseProvider).auth.currentUser?.email;
    final info = ref.watch(_packageInfoProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncView(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        builder: (p) {
          final currency = p?.currency ?? 'PHP';
          final currencies = {...supportedCurrencies, currency}.toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            ContentWidth(
              maxWidth: 700,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionHeader('Profile'),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Display name'),
                      subtitle: Text(p?.displayName?.isNotEmpty == true ? p!.displayName! : 'Not set'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editName(p?.displayName),
                    ),
                    ListTile(
                      leading: const Icon(Icons.alternate_email),
                      title: const Text('Email'),
                      subtitle: Text(email ?? '—'),
                    ),
                  ]),
                ),
                const SectionHeader('Preferences'),
                Card(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('Currency'),
                      subtitle: const Text('Changes how amounts are shown, not their values.'),
                      trailing: DropdownButton<String>(
                        value: currency,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final c in currencies)
                            DropdownMenuItem(value: c, child: Text('$c  ${currencySymbol(c)}')),
                        ],
                        onChanged: (c) {
                          if (c != null && c != currency) _updateProfile(currency: c);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Theme', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                                value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                            ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                            ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                          ],
                          selected: {themeMode},
                          onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                        ),
                      ]),
                    ),
                  ]),
                ),
                const SectionHeader('About'),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Version'),
                      subtitle: Text(info == null ? '…' : '${info.version} (build ${info.buildNumber})'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.system_update_outlined),
                      title: const Text('Check for updates'),
                      trailing: _checkingUpdate
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: _checkingUpdate || currentPlatformName == null ? null : _checkForUpdate,
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
