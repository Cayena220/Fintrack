import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/offline_store.dart';
import '../formatters.dart';
import '../icons.dart';
import '../theme.dart';

/// Turns exceptions into short, human messages.
String friendlyError(Object error) {
  if (error is AuthException) return error.message;
  if (error is SyncRejected) return error.message;
  if (error is PostgrestException) {
    switch (error.code) {
      case '23503':
        return 'This item is still used by other records.';
      case '23505':
        return 'That already exists.';
      case '23514':
        return 'Some values are not valid. Please check the form.';
      case '42501':
        return 'You do not have permission to do that.';
    }
    return error.message;
  }
  if (isNetworkError(error)) {
    return "You're offline. Transactions save offline, but this change needs an internet connection.";
  }
  return 'Something went wrong. Please try again.';
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

void showError(BuildContext context, Object error) => showSnack(context, friendlyError(error));

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  minimumSize: const Size(64, 40),
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Renders an [AsyncValue] with consistent loading and error states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Keep showing previous data while refreshing.
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(friendlyError(value.error!), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ]),
        ),
      );
    }
    return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Round tinted icon used for categories, accounts and goals.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40});

  final String icon;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(iconFor(icon), color: c, size: size * 0.55),
    );
  }
}

/// Amount colored by direction (green income, red expense).
class MoneyText extends StatelessWidget {
  const MoneyText(this.cents, {super.key, required this.currency, this.signed = true, this.style, this.neutral = false});

  final int cents;
  final String currency;
  final bool signed;
  final bool neutral;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = neutral || cents == 0
        ? null
        : (cents > 0 ? MoneyColors.income(context) : MoneyColors.expense(context));
    return Text(
      formatMoney(cents, currency, signed: signed),
      style: (style ?? const TextStyle()).copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }
}

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCurrent = monthStart(DateTime.now()) == monthStart(month);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'Previous month',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(addMonths(month, -1)),
      ),
      TextButton(
        onPressed: isCurrent ? null : () => onChanged(monthStart(DateTime.now())),
        child: Text(formatMonth(month), style: Theme.of(context).textTheme.titleMedium),
      ),
      IconButton(
        tooltip: 'Next month',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => onChanged(addMonths(month, 1)),
      ),
    ]);
  }
}

class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({super.key, required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in appColors)
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onChanged(c),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: c == selected
                  ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                  : null,
            ),
          ),
        ),
    ]);
  }
}

class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({super.key, required this.selected, required this.color, required this.onChanged});

  final String selected;
  final int color;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final entry in appIcons.entries)
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(entry.key),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: entry.key == selected ? Color(color).withValues(alpha: 0.18) : null,
              borderRadius: BorderRadius.circular(10),
              border: entry.key == selected ? Border.all(color: Color(color), width: 2) : null,
            ),
            child: Icon(entry.value, color: entry.key == selected ? Color(color) : null, size: 22),
          ),
        ),
    ]);
  }
}

/// Section title used on dashboard-style pages.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ?action,
      ]),
    );
  }
}

/// Centers content and caps its width on wide (desktop) windows.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 900});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}
