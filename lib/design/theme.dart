/// Material theme assembled from the Mukai tokens.
///
/// Deliberate translations for iOS, all in one place:
///   * Typeface is left unset, so iOS renders SF Pro — the faithful match for
///     the app's `-apple-system` fallback (Inter is a web-only nicety there).
///   * Radii run one step rounder than the desktop 6/10/14 scale, because touch
///     targets read tighter than cursor targets.
///   * `--shadow` (0 20px 70px / 0 4px 18px) is scaled down for small screens.
///
/// Nothing here should hard-code a colour: it all comes from [MukaiColors].
library;

import 'package:flutter/cupertino.dart'
    show CupertinoPageTransitionsBuilder, CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';

/// Corner radii. `desktop*` values are kept for parity with `tokens.css`.
abstract final class MukaiRadii {
  static const double chip = 8;
  static const double control = 12;
  static const double card = 16;
  static const double cardLarge = 20;
  static const double sheet = 28;
  static const double pill = 999;

  static const double desktopSmall = 6;
  static const double desktopMedium = 10;
  static const double desktopLarge = 14;
}

/// Spacing rhythm. The desktop app leans on 6/10/14/18/24/32.
abstract final class MukaiSpace {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double screen = 20;
}

/// Motion. Ported from the CSS transitions (120–240ms, ease-out).
abstract final class MukaiMotion {
  static const Duration instant = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve springy = Curves.easeOutBack;
}

/// Layered soft shadows derived from `--shadow` / `--modal-shadow`.
abstract final class MukaiShadows {
  static List<BoxShadow> card(Brightness brightness) {
    final Color tint = brightness == Brightness.dark
        ? const Color(0xFF000000)
        : const Color(0xFF12232E);
    return <BoxShadow>[
      BoxShadow(
        color: tint.withValues(
          alpha: brightness == Brightness.dark ? 0.30 : 0.018,
        ),
        blurRadius: 32,
        offset: const Offset(0, 12),
      ),
      BoxShadow(
        color: tint.withValues(
          alpha: brightness == Brightness.dark ? 0.18 : 0.012,
        ),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ];
  }

  static List<BoxShadow> floating(Brightness brightness) {
    final Color tint = brightness == Brightness.dark
        ? const Color(0xFF000000)
        : const Color(0xFF12232E);
    return <BoxShadow>[
      BoxShadow(
        color: tint.withValues(
          alpha: brightness == Brightness.dark ? 0.42 : 0.035,
        ),
        blurRadius: 48,
        offset: const Offset(0, 18),
      ),
      BoxShadow(
        color: tint.withValues(
          alpha: brightness == Brightness.dark ? 0.24 : 0.018,
        ),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> sheet(Brightness brightness) {
    final Color tint = brightness == Brightness.dark
        ? const Color(0xFF000000)
        : const Color(0xFF12232E);
    return <BoxShadow>[
      BoxShadow(
        color: tint.withValues(
          alpha: brightness == Brightness.dark ? 0.55 : 0.14,
        ),
        blurRadius: 60,
        offset: const Offset(0, -10),
      ),
    ];
  }
}

/// Text styles at iOS sizes, in Mukai's voice: tight headings, generous body.
TextTheme mukaiTextTheme(MukaiColors colors) {
  TextStyle step(
    double size, {
    double? height,
    double tracking = 0,
    FontWeight weight = FontWeight.w400,
    Color? color,
    FontFeature? feature,
  }) => TextStyle(
    fontSize: size,
    height: height == null ? null : height / size,
    letterSpacing: tracking,
    fontWeight: weight,
    color: color ?? colors.textBody,
    fontFeatures: feature == null ? null : <FontFeature>[feature],
  );

  return TextTheme(
    displayLarge: step(
      34,
      height: 40,
      tracking: -1.1,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    displaySmall: step(
      29,
      height: 35,
      tracking: -0.9,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    headlineMedium: step(
      24,
      height: 30,
      tracking: -0.7,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    headlineSmall: step(
      21,
      height: 27,
      tracking: -0.5,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    titleLarge: step(
      18,
      height: 24,
      tracking: -0.3,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    titleMedium: step(
      15.5,
      height: 21,
      tracking: -0.2,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    titleSmall: step(
      14,
      height: 19,
      tracking: -0.1,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    bodyLarge: step(16, height: 24),
    bodyMedium: step(14.5, height: 22),
    bodySmall: step(13, height: 19, color: colors.textSecondary),
    labelLarge: step(
      14.5,
      height: 20,
      weight: FontWeight.w600,
      color: colors.ink,
    ),
    labelMedium: step(
      12.5,
      height: 17,
      weight: FontWeight.w600,
      color: colors.textSecondary,
    ),
    labelSmall: step(
      11,
      height: 15,
      tracking: 1.2,
      weight: FontWeight.w700,
      color: colors.accentInk,
      feature: const FontFeature.tabularFigures(),
    ),
  );
}

/// One factory for both modes — pass the resolved brightness.
ThemeData mukaiTheme(MukaiPreferences preferences, Brightness brightness) {
  final MukaiColors colors = MukaiColors.from(preferences, brightness);
  final AccentPalette accent = colors.accent;
  final bool dark = colors.isDark;

  // Built from a seed rather than the bare ColorScheme constructor: the seed
  // form has a stable signature, and only the roles we care about are
  // overridden. Widgets read MukaiColors, so the scheme mainly drives
  // framework internals (splashes, M3 defaults).
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: accent.accent,
        brightness: brightness,
      ).copyWith(
        primary: accent.accent,
        onPrimary: colors.textOnAccent,
        primaryContainer: accent.soft,
        onPrimaryContainer: accent.text,
        secondary: accent.nav,
        onSecondary: colors.textOnAccent,
        secondaryContainer: accent.soft,
        onSecondaryContainer: accent.text,
        tertiary: accent.glow,
        error: dark ? const Color(0xFFE0836F) : const Color(0xFFB3402B),
        onError: colors.textOnAccent,
        errorContainer: dark
            ? const Color(0xFF3C2723)
            : const Color(0xFFFAEDEA),
        onErrorContainer: dark
            ? const Color(0xFFF2C7BC)
            : const Color(0xFF6E2718),
        surface: colors.canvas,
        onSurface: colors.ink,
        surfaceContainerLowest: colors.canvas,
        surfaceContainerLow: colors.cardMuted,
        surfaceContainer: colors.cardMuted,
        surfaceContainerHigh: colors.cardMuted,
        surfaceContainerHighest: colors.cardMuted,
        onSurfaceVariant: colors.textSecondary,
        outline: colors.hairlineStrong,
        outlineVariant: colors.hairline,
        inverseSurface: dark
            ? const Color(0xFFE6EDEA)
            : const Color(0xFF263B45),
        onInverseSurface: dark
            ? const Color(0xFF1C252A)
            : const Color(0xFFF7F9F5),
      );

  final TextTheme text = mukaiTextTheme(colors);

  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(MukaiRadii.control),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    colorScheme: scheme,
    // Adaptive iOS switches discard SwitchThemeData; tint their native theme.
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: accent.accent,
      brightness: brightness,
      applyThemeToAll: true,
    ),
    scaffoldBackgroundColor: colors.canvas,
    canvasColor: colors.canvas,
    // iOS reads as calmer with a ripple than the M3 sparkle.
    splashFactory: InkRipple.splashFactory,
    extensions: <ThemeExtension<dynamic>>[colors],
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: colors.textSecondary, size: 20),
    primaryIconTheme: IconThemeData(color: accent.accent, size: 20),
    dividerColor: colors.hairline,
    dividerTheme: DividerThemeData(
      color: colors.hairline,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent.accent,
      selectionColor: accent.accent.withValues(alpha: 0.24),
      selectionHandleColor: accent.accent,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent.text,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MukaiRadii.control),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent.accent,
        foregroundColor: colors.textOnAccent,
        disabledBackgroundColor: dark
            ? accent.accent.withValues(alpha: 0.35)
            : accent.accent.withValues(alpha: 0.40),
        disabledForegroundColor: colors.textOnAccent.withValues(alpha: 0.75),
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MukaiRadii.control),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.canvas,
      hintStyle: text.bodyLarge?.copyWith(color: colors.textSoft),
      labelStyle: text.bodySmall?.copyWith(color: colors.textSecondary),
      floatingLabelStyle: text.labelMedium?.copyWith(color: accent.text),
      helperStyle: text.bodySmall?.copyWith(
        color: colors.textSecondary,
        height: 1.5,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      enabledBorder: border(colors.hairlineStrong),
      border: border(colors.hairlineStrong),
      focusedBorder: border(accent.accent, 1.6),
      errorBorder: border(
        dark ? const Color(0xFFE0836F) : const Color(0xFFB3402B),
      ),
      focusedErrorBorder: border(
        dark ? const Color(0xFFE0836F) : const Color(0xFFB3402B),
        1.6,
      ),
      disabledBorder: border(colors.hairline),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.textSecondary,
      textColor: colors.ink,
      minVerticalPadding: 10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.canvas,
      modalBarrierColor: colors.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MukaiRadii.sheet),
        ),
      ),
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
    ),
    // Dialogs and TabBar are intentionally not themed: this client uses sheets
    // and its own tab bar, which keeps the theme on long-stable APIs.
    popupMenuTheme: PopupMenuThemeData(
      color: colors.card,
      elevation: 12,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MukaiRadii.card),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF2E3A41) : const Color(0xFF263B45),
      contentTextStyle: text.bodySmall?.copyWith(
        color: const Color(0xFFF2F6F4),
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MukaiRadii.control),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2E3A41) : const Color(0xFF263B45),
        borderRadius: BorderRadius.circular(MukaiRadii.chip),
      ),
      textStyle: text.bodySmall?.copyWith(color: const Color(0xFFF2F6F4)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      waitDuration: const Duration(milliseconds: 420),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.textOnAccent
            : colors.canvas,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? accent.accent
            : (dark ? colors.hairlineStrong : const Color(0xFFE4E9E5)),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent.accent,
      linearTrackColor: accent.soft,
      circularTrackColor: accent.soft,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.canvas,
      foregroundColor: colors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    // Swipe-from-the-left, like every other screen on the device.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Status-bar styling that follows the selected palette's rail colour.
SystemUiOverlayStyle mukaiOverlayStyle(MukaiColors colors) => colors.isDark
    ? SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: Colors.transparent,
      )
    : SystemUiOverlayStyle.dark.copyWith(
        systemNavigationBarColor: Colors.transparent,
      );
