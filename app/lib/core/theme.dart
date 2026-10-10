import 'package:flutter/material.dart';

const _seed = Color(0xFF059669);

/// Semantic colors for money that read well in light and dark mode.
class MoneyColors {
  static Color income(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF34D399) : const Color(0xFF047857);
  static Color expense(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFB7185) : const Color(0xFFBE123C);
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
