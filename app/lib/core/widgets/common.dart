import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/offline_store.dart';
import '../formatters.dart';
import '../icons.dart';
import '../theme.dart';

/// Dropdowns take their arrow from the app's icon set, not Material Icons.
const dropdownIcon = Icon(Symbols.expand_more_rounded);

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
            const _StateIcon(Symbols.cloud_off_rounded, error: true),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(friendlyError(value.error!), textAlign: TextAlign.center),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Symbols.refresh_rounded), label: const Text('Retry')),
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
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _StateIcon(icon),
          const SizedBox(height: 12),
          Text(title, style: text.title, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(message!,
                  style: text.body.copyWith(color: FinColors.of(context).inkMuted), textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// The 64px tile behind an empty or failed-load state's icon.
class _StateIcon extends StatelessWidget {
  const _StateIcon(this.icon, {this.error = false});

  final IconData icon;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = FinColors.of(context);
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: error ? colors.expenseSoft : colors.surfaceSunken,
        borderRadius: BorderRadius.circular(FinRadius.lg),
      ),
      child: Icon(icon, size: 30, color: error ? colors.expense : colors.inkMuted),
    );
  }
}

/// Tinted squircle that carries a category's, account's or goal's icon.
/// The glyph is darkened toward ink (or white in dark mode) so light
/// category colors still read. [round] is only for chips.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40, this.round = false});

  final String icon;
  final int color;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final colors = FinColors.of(context);
    final c = Color(color);
    final radius = round ? size / 2 : (size >= 48 ? FinRadius.md : FinRadius.sm);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colors.categoryTint(c), borderRadius: BorderRadius.circular(radius)),
      child: Icon(iconFor(icon), color: colors.categoryInk(c), size: (size * 0.55).roundToDouble()),
    );
  }
}

/// What an amount means, which decides its sign and color. Direction is
/// shown by the sign first; red is for trouble, not for spending.
enum AmountKind {
  /// +₱32,000.00 in income green.
  income,

  /// −₱1,240.00 in ink.
  expense,

  /// No sign, ink: transfers, and totals whose label already says which way
  /// the money went.
  plain,

  /// Ink, or expense red with a minus when negative.
  balance,

  /// Income green with a plus, or expense red with a minus.
  net,
}

/// A money figure in tabular numerals, signed and colored by [kind].
class MoneyText extends StatelessWidget {
  const MoneyText(this.cents,
      {super.key, required this.currency, this.kind = AmountKind.balance, this.over = false, this.style});

  final int cents;
  final String currency;
  final AmountKind kind;

  /// Paints an over-budget figure in expense red.
  final bool over;

  /// Defaults to body-strong.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = FinColors.of(context);
    final shown = switch (kind) {
      AmountKind.income || AmountKind.plain => cents.abs(),
      AmountKind.expense => -cents.abs(),
      AmountKind.balance || AmountKind.net => cents,
    };
    final trouble = over || (shown < 0 && (kind == AmountKind.balance || kind == AmountKind.net));
    final grew = shown > 0 && (kind == AmountKind.income || kind == AmountKind.net);
    return Text(
      formatMoney(shown, currency, signed: kind == AmountKind.income || kind == AmountKind.net),
      style: (style ?? Theme.of(context).textTheme.bodyStrong)
          .tabular
          .copyWith(color: trouble ? colors.expense : (grew ? colors.income : colors.ink)),
    );
  }
}

/// An 8px pill on a sunken track, for budgets and goals. It never shows a
/// level on its own: the card beside it says it in words and with an icon.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.ratio, required this.color, required this.label, this.height = 8});

  final double ratio;
  final Color color;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return Semantics(
      label: label,
      value: '${(ratio * 100).round()}%',
      child: Container(
        height: height,
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(color: FinColors.of(context).surfaceSunken, borderRadius: radius),
        child: FractionallySizedBox(
          widthFactor: ratio.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: radius)),
        ),
      ),
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
    final text = Theme.of(context).textTheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'Previous month',
        icon: const Icon(Symbols.chevron_left_rounded),
        onPressed: () => onChanged(addMonths(month, -1)),
      ),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(150, 40)),
        onPressed: isCurrent ? null : () => onChanged(monthStart(DateTime.now())),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(formatMonth(month), style: text.title),
          if (!isCurrent)
            Text('Back to this month', style: text.caption.copyWith(color: FinColors.of(context).fin)),
        ]),
      ),
      IconButton(
        tooltip: 'Next month',
        icon: const Icon(Symbols.chevron_right_rounded),
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
    final colors = FinColors.of(context);
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
              // A 2px surface gap inside a 2px ink ring: a shape cue that works for every swatch.
              boxShadow: c == selected
                  ? [
                      BoxShadow(color: colors.ink, spreadRadius: 4),
                      BoxShadow(color: colors.surface, spreadRadius: 2),
                    ]
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
    final colors = FinColors.of(context);
    final glyph = colors.categoryInk(Color(color));
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final entry in appIcons.entries)
        InkWell(
          borderRadius: BorderRadius.circular(FinRadius.sm),
          onTap: () => onChanged(entry.key),
          child: Container(
            width: 44,
            height: 44,
            decoration: entry.key == selected
                ? BoxDecoration(
                    color: colors.categoryTint(Color(color)),
                    borderRadius: BorderRadius.circular(FinRadius.sm),
                    border: Border.all(color: glyph, width: 2),
                  )
                : null,
            child: Icon(entry.value, color: entry.key == selected ? glyph : colors.inkMuted, size: 22),
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
        Expanded(child: Text(title, style: Theme.of(context).textTheme.title)),
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
