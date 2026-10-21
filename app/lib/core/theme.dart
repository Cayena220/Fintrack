import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// FinTrack design tokens: Shallows (light, the default) and Night swim (dark).
///
/// Every color the app paints with lives here, under its design-system name.
/// The [ColorScheme] in [buildTheme] is built from these, so Material widgets
/// pick them up too. Read them with [FinColors.of].
@immutable
class FinColors extends ThemeExtension<FinColors> {
  const FinColors({
    required this.brightness,
    required this.paper,
    required this.surface,
    required this.surfaceSunken,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkMuted,
    required this.deep,
    required this.onDeep,
    required this.onDeepMuted,
    required this.foam,
    required this.onDeepExpense,
    required this.lineOnDeep,
    required this.fin,
    required this.finHover,
    required this.onFin,
    required this.finSoft,
    required this.expense,
    required this.expenseSoft,
    required this.onDanger,
    required this.warning,
    required this.sun,
    required this.warningSoft,
  });

  final Brightness brightness;

  /// Screen background.
  final Color paper;

  /// Cards, lists, sheets, dialogs and the nav bar.
  final Color surface;

  /// Wells and progress-bar tracks.
  final Color surfaceSunken;

  /// Hairlines: card borders and dividers. Never the only edge of a control.
  final Color line;

  /// Borders that carry meaning: fields, unselected chips, secondary buttons.
  final Color lineStrong;

  /// Primary text and icons. Also routine expense amounts.
  final Color ink;

  /// Secondary text: dates, account names, captions.
  final Color inkMuted;

  /// Deep water: the balance card and the sync banner only.
  final Color deep;
  final Color onDeep;
  final Color onDeepMuted;

  /// The logo's wave. Income on [deep]; never text on paper or surface.
  final Color foam;

  /// Expense and negative figures on [deep] only.
  final Color onDeepExpense;
  final Color lineOnDeep;

  /// The one action color.
  final Color fin;
  final Color finHover;
  final Color onFin;
  final Color finSoft;

  /// Trouble, not spending: over budget, negative balances, destructive actions.
  final Color expense;
  final Color expenseSoft;
  final Color onDanger;

  /// A budget past its alert threshold: [warning] text, [sun] bar, [warningSoft] card.
  final Color warning;
  final Color sun;
  final Color warningSoft;

  /// Money that grows. Alias of [fin].
  Color get income => fin;

  /// Delete buttons and form errors. Alias of [expense].
  Color get danger => expense;

  /// Glyph (and goal bar) color for a stored category color: mixed 60/40
  /// toward ink in Shallows and toward white in Night swim, so even the light
  /// picks clear 3:1.
  Color categoryInk(Color color) =>
      Color.lerp(color, brightness == Brightness.dark ? Colors.white : ink, 0.4)!;

  /// Badge tile for a stored category color: 16% on surface (22% in Night swim).
  Color categoryTint(Color color) =>
      Color.alphaBlend(color.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.16), surface);

  static const light = FinColors(
    brightness: Brightness.light,
    paper: Color(0xFFF5F6F1),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFECEEE7),
    line: Color(0xFFDCE0D6),
    lineStrong: Color(0xFF7D8983),
    ink: Color(0xFF0D2420),
    inkMuted: Color(0xFF4A5B55),
    deep: Color(0xFF0C3B31),
    onDeep: Color(0xFFF1FAF5),
    onDeepMuted: Color(0xFFA9D9C4),
    foam: Color(0xFFA7F3D0),
    onDeepExpense: Color(0xFFFFB4A3),
    lineOnDeep: Color(0x2EF1FAF5),
    fin: Color(0xFF087A58),
    finHover: Color(0xFF066548),
    onFin: Color(0xFFFFFFFF),
    finSoft: Color(0xFFDBF3E7),
    expense: Color(0xFFB3361F),
    expenseSoft: Color(0xFFFBE6DF),
    onDanger: Color(0xFFFFFFFF),
    warning: Color(0xFF8A5000),
    sun: Color(0xFFB8740C),
    warningSoft: Color(0xFFFCEFD3),
  );

  static const dark = FinColors(
    brightness: Brightness.dark,
    paper: Color(0xFF0A1412),
    surface: Color(0xFF111E1B),
    surfaceSunken: Color(0xFF070F0D),
    line: Color(0xFF22332E),
    lineStrong: Color(0xFF62786F),
    ink: Color(0xFFE8F1EC),
    inkMuted: Color(0xFF9DB1A9),
    deep: Color(0xFF1A5446),
    onDeep: Color(0xFFF1FAF5),
    onDeepMuted: Color(0xFFA9D9C4),
    foam: Color(0xFFA7F3D0),
    onDeepExpense: Color(0xFFFFB4A3),
    lineOnDeep: Color(0x2EF1FAF5),
    fin: Color(0xFF3DD39C),
    finHover: Color(0xFF6EE2B6),
    onFin: Color(0xFF04241A),
    finSoft: Color(0xFF123A2F),
    expense: Color(0xFFFF8F78),
    expenseSoft: Color(0xFF3B1A13),
    onDanger: Color(0xFF2A0A04),
    warning: Color(0xFFF2B84B),
    sun: Color(0xFFF0AC2E),
    warningSoft: Color(0xFF372809),
  );

  /// The theme's tokens, or the defaults for its brightness when the theme
  /// was not built by [buildTheme] (widget tests).
  static FinColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FinColors>() ?? (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  FinColors copyWith({
    Brightness? brightness,
    Color? paper,
    Color? surface,
    Color? surfaceSunken,
    Color? line,
    Color? lineStrong,
    Color? ink,
    Color? inkMuted,
    Color? deep,
    Color? onDeep,
    Color? onDeepMuted,
    Color? foam,
    Color? onDeepExpense,
    Color? lineOnDeep,
    Color? fin,
    Color? finHover,
    Color? onFin,
    Color? finSoft,
    Color? expense,
    Color? expenseSoft,
    Color? onDanger,
    Color? warning,
    Color? sun,
    Color? warningSoft,
  }) {
    return FinColors(
      brightness: brightness ?? this.brightness,
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      deep: deep ?? this.deep,
      onDeep: onDeep ?? this.onDeep,
      onDeepMuted: onDeepMuted ?? this.onDeepMuted,
      foam: foam ?? this.foam,
      onDeepExpense: onDeepExpense ?? this.onDeepExpense,
      lineOnDeep: lineOnDeep ?? this.lineOnDeep,
      fin: fin ?? this.fin,
      finHover: finHover ?? this.finHover,
      onFin: onFin ?? this.onFin,
      finSoft: finSoft ?? this.finSoft,
      expense: expense ?? this.expense,
      expenseSoft: expenseSoft ?? this.expenseSoft,
      onDanger: onDanger ?? this.onDanger,
      warning: warning ?? this.warning,
      sun: sun ?? this.sun,
      warningSoft: warningSoft ?? this.warningSoft,
    );
  }

  @override
  FinColors lerp(FinColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return FinColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      paper: mix(paper, other.paper),
      surface: mix(surface, other.surface),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      line: mix(line, other.line),
      lineStrong: mix(lineStrong, other.lineStrong),
      ink: mix(ink, other.ink),
      inkMuted: mix(inkMuted, other.inkMuted),
      deep: mix(deep, other.deep),
      onDeep: mix(onDeep, other.onDeep),
      onDeepMuted: mix(onDeepMuted, other.onDeepMuted),
      foam: mix(foam, other.foam),
      onDeepExpense: mix(onDeepExpense, other.onDeepExpense),
      lineOnDeep: mix(lineOnDeep, other.lineOnDeep),
      fin: mix(fin, other.fin),
      finHover: mix(finHover, other.finHover),
      onFin: mix(onFin, other.onFin),
      finSoft: mix(finSoft, other.finSoft),
      expense: mix(expense, other.expense),
      expenseSoft: mix(expenseSoft, other.expenseSoft),
      onDanger: mix(onDanger, other.onDanger),
      warning: mix(warning, other.warning),
      sun: mix(sun, other.sun),
      warningSoft: mix(warningSoft, other.warningSoft),
    );
  }
}

/// Corner radii. Badges [sm], buttons and fields [md], cards and dialogs
/// [lg], the balance card and sheets [xl].
abstract final class FinRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

const _displayFamily = 'Bricolage Grotesque';
const _sansFamily = 'Instrument Sans';

/// Tabular figures, so amounts line up in columns.
const tabularFigures = [FontFeature.tabularFigures()];

/// The design system's type styles by name. [buildTheme] maps them onto the
/// Material roles; these getters read them back.
extension FinTextStyles on TextTheme {
  /// 44/48 800, Bricolage. The total balance; one per screen.
  TextStyle get balance => displayLarge!;

  /// 36/40 800, Bricolage. Onboarding headlines.
  TextStyle get display => displayMedium!;

  /// 24/30 700, Bricolage. App bar titles and section totals.
  TextStyle get headline => headlineMedium!;

  /// 17/24 600. Section headers, card and dialog titles.
  TextStyle get title => titleMedium!;

  /// 15/22. Running text and messages.
  TextStyle get body => bodyMedium!;

  /// 15/22 600. Row titles and row amounts.
  TextStyle get bodyStrong => titleSmall!;

  /// 14/20 600. Buttons, chips, tabs.
  TextStyle get label => labelLarge!;

  /// 13/18. Row subtitles, helper text, metadata.
  TextStyle get caption => bodySmall!;

  /// 11/14 600. Nav labels, chart axes and legends only.
  TextStyle get micro => labelSmall!;
}

extension TabularFigures on TextStyle {
  TextStyle get tabular => copyWith(fontFeatures: tabularFigures);
}

TextTheme _textTheme(FinColors c) {
  // Sizes and tracking are in px, converted from the spec's line heights and ems.
  TextStyle style(String family, double size, double lineHeight, FontWeight weight, [double tracking = 0]) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: lineHeight / size,
        leadingDistribution: TextLeadingDistribution.even,
        fontWeight: weight,
        letterSpacing: tracking,
        color: c.ink,
      );

  final balance = style(_displayFamily, 44, 48, FontWeight.w800, -1.1).tabular;
  final display = style(_displayFamily, 36, 40, FontWeight.w800, -0.9);
  final headline = style(_displayFamily, 24, 30, FontWeight.w700, -0.36);
  final title = style(_sansFamily, 17, 24, FontWeight.w600);
  final body = style(_sansFamily, 15, 22, FontWeight.w400);
  final bodyStrong = style(_sansFamily, 15, 22, FontWeight.w600);
  final label = style(_sansFamily, 14, 20, FontWeight.w600, 0.07);
  final caption = style(_sansFamily, 13, 18, FontWeight.w400);
  final micro = style(_sansFamily, 11, 14, FontWeight.w600, 0.22);

  return TextTheme(
    displayLarge: balance,
    displayMedium: display,
    displaySmall: display,
    headlineLarge: headline,
    headlineMedium: headline,
    headlineSmall: headline,
    titleLarge: headline,
    titleMedium: title,
    titleSmall: bodyStrong,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: label,
    labelMedium: micro,
    labelSmall: micro,
  );
}

ColorScheme _colorScheme(FinColors c) {
  final dark = c.brightness == Brightness.dark;
  return ColorScheme(
    brightness: c.brightness,
    primary: c.fin,
    onPrimary: c.onFin,
    primaryContainer: c.finSoft,
    onPrimaryContainer: c.ink,
    secondary: c.deep,
    onSecondary: c.onDeep,
    secondaryContainer: c.finSoft,
    onSecondaryContainer: c.ink,
    tertiary: c.warning,
    onTertiary: c.surface,
    tertiaryContainer: c.warningSoft,
    onTertiaryContainer: c.ink,
    error: c.expense,
    onError: c.onDanger,
    errorContainer: c.expenseSoft,
    onErrorContainer: c.ink,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.inkMuted,
    surfaceDim: c.surfaceSunken,
    surfaceBright: c.surface,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surfaceSunken,
    outline: c.lineStrong,
    outlineVariant: c.line,
    shadow: dark ? Colors.black : const Color(0xFF0D2420),
    scrim: Colors.black,
    inverseSurface: c.ink,
    onInverseSurface: c.paper,
    inversePrimary: dark ? FinColors.light.fin : FinColors.dark.fin,
    surfaceTint: Colors.transparent,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? FinColors.dark : FinColors.light;
  final scheme = _colorScheme(c);
  final text = _textTheme(c);

  // Material Symbols Rounded: outline, weight 450, 24px optical size.
  const icons = IconThemeData(size: 24, fill: 0, weight: 450, grade: 0, opticalSize: 24);
  RoundedRectangleBorder rounded(double radius, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);
  OutlineInputBorder field(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(FinRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  // Hover and press darken the fill; disabled is 45% opacity, not a new color.
  WidgetStateProperty<Color> fill(Color base, Color hover) => WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return base.withValues(alpha: base.a * 0.45);
        if (states.contains(WidgetState.pressed) || states.contains(WidgetState.hovered)) return hover;
        return base;
      });
  WidgetStateProperty<Color> ink(Color color) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? color.withValues(alpha: 0.45) : color);
  // The fill change is the hover and press feedback; keep an overlay only for keyboard focus.
  WidgetStateProperty<Color> focusOverlay(Color color) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? color.withValues(alpha: 0.12) : Colors.transparent);
  ButtonStyle button({required Color background, required Color hover, required Color foreground}) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        shape: WidgetStatePropertyAll(rounded(FinRadius.md)),
        textStyle: WidgetStatePropertyAll(text.label),
        iconSize: const WidgetStatePropertyAll(20),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: fill(background, hover),
        foregroundColor: ink(foreground),
        iconColor: ink(foreground),
        overlayColor: focusOverlay(foreground),
      );
  bool selected(Set<WidgetState> states) => states.contains(WidgetState.selected);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    // Not ThemeData.fontFamily: that would override Bricolage in the display styles.
    textTheme: text,
    primaryTextTheme: text.apply(bodyColor: c.onFin, displayColor: c.onFin),
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.surface,
    shadowColor: scheme.shadow,
    dividerColor: c.line,
    iconTheme: icons.copyWith(color: c.ink),
    // The framework's own back and close buttons use the same icon set as the app.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const Icon(Symbols.arrow_back_rounded),
      closeButtonIconBuilder: (context) => const Icon(Symbols.close_rounded),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.headline,
      iconTheme: icons.copyWith(color: c.ink),
      actionsIconTheme: icons.copyWith(color: c.ink),
    ),
    // Flat: surface on paper with a hairline, no shadow.
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: rounded(FinRadius.lg, BorderSide(color: c.line)),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      // The label stays visible above the value; never placeholder-only.
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: field(c.lineStrong),
      enabledBorder: field(c.lineStrong),
      focusedBorder: field(c.fin, 2),
      errorBorder: field(c.danger),
      focusedErrorBorder: field(c.danger, 2),
      disabledBorder: field(c.line),
      labelStyle: text.body.copyWith(color: c.inkMuted),
      // InputDecorator draws a floating label at 0.75 of this size; this lands it on the 14px label style.
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) => text.label.copyWith(
            fontSize: text.label.fontSize! / 0.75,
            letterSpacing: text.label.letterSpacing! / 0.75,
            color: states.contains(WidgetState.error) ? c.danger : c.ink,
          )),
      hintStyle: text.body.copyWith(color: c.inkMuted),
      helperStyle: text.caption.copyWith(color: c.inkMuted),
      errorStyle: text.caption.copyWith(color: c.danger),
      prefixStyle: TextStyle(color: c.inkMuted),
      suffixStyle: TextStyle(color: c.inkMuted),
      prefixIconColor: c.inkMuted,
      suffixIconColor: c.inkMuted,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.fin),
    // primary
    filledButtonTheme: FilledButtonThemeData(
      style: button(background: c.fin, hover: c.finHover, foreground: c.onFin),
    ),
    // secondary
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(background: c.surface, hover: c.surfaceSunken, foreground: c.ink).copyWith(
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.disabled) ? c.lineStrong.withValues(alpha: 0.45) : c.lineStrong)),
      ),
    ),
    // quiet
    textButtonTheme: TextButtonThemeData(
      style: button(background: Colors.transparent, hover: c.finSoft, foreground: c.fin).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: ink(c.ink),
        iconColor: ink(c.ink),
        backgroundColor: fill(Colors.transparent, c.surfaceSunken),
        overlayColor: focusOverlay(c.ink),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.fin,
      foregroundColor: c.onFin,
      hoverColor: c.finHover,
      focusColor: c.finHover,
      shape: rounded(FinRadius.lg),
      extendedTextStyle: text.label,
      iconSize: 24,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      // A sunken well; the chosen segment lifts to surface with a fin icon.
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        shape: WidgetStatePropertyAll(rounded(FinRadius.md)),
        side: WidgetStatePropertyAll(BorderSide(color: c.surfaceSunken, width: 4)),
        textStyle: WidgetStatePropertyAll(text.label),
        iconSize: const WidgetStatePropertyAll(18),
        backgroundColor: WidgetStateProperty.resolveWith((s) => selected(s) ? c.surface : c.surfaceSunken),
        foregroundColor: WidgetStateProperty.resolveWith((s) => selected(s) ? c.ink : c.inkMuted),
        iconColor: WidgetStateProperty.resolveWith((s) => selected(s) ? c.fin : c.inkMuted),
        overlayColor: focusOverlay(c.ink),
      ),
    ),
    chipTheme: ChipThemeData(
      // Selection reads by border weight, not only tint.
      color: WidgetStateProperty.resolveWith((s) => selected(s) ? c.finSoft : c.surface),
      side: WidgetStateBorderSide.resolveWith(
          (s) => selected(s) ? BorderSide(color: c.fin, width: 2) : BorderSide(color: c.lineStrong)),
      shape: const StadiumBorder(),
      labelStyle: text.label.copyWith(color: c.ink),
      showCheckmark: false,
      surfaceTintColor: Colors.transparent,
      iconTheme: icons.copyWith(color: c.fin, size: 18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.fin,
      linearTrackColor: c.surfaceSunken,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 8,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.finSoft,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.micro.copyWith(color: selected(s) ? c.ink : c.inkMuted)),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => icons.copyWith(size: 22, color: selected(s) ? c.fin : c.inkMuted)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.finSoft,
      indicatorShape: const StadiumBorder(),
      selectedIconTheme: icons.copyWith(size: 22, color: c.fin),
      unselectedIconTheme: icons.copyWith(size: 22, color: c.inkMuted),
      selectedLabelTextStyle: text.micro.copyWith(color: c.ink),
      unselectedLabelTextStyle: text.micro.copyWith(color: c.inkMuted),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.inkMuted,
      titleTextStyle: text.bodyStrong,
      subtitleTextStyle: text.caption.copyWith(color: c.inkMuted),
      leadingAndTrailingTextStyle: text.bodyStrong.tabular,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded(FinRadius.lg),
      titleTextStyle: text.title,
      contentTextStyle: text.body.copyWith(color: c.inkMuted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: c.lineStrong,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FinRadius.xl))),
    ),
    // Inverted: ink fill, paper text.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: text.body.copyWith(color: c.paper),
      actionTextColor: c.paper,
      shape: rounded(FinRadius.md),
      elevation: 6,
    ),
  );
}
