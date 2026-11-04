/// Mukai appearance system — the Flutter port of the app's `tokens.css` +
/// `features/appearance/themes.ts`.
///
/// Two orthogonal axes, exactly like the desktop app:
///   * [ColorMode]  — light / dark / system  (`:root[data-mode]`)
///   * [MukaiThemeId] — one of six named accent palettes (`--theme-*`)
///
/// Everything a widget needs lands in one [ThemeExtension] ([MukaiColors]), so
/// a screen says `MukaiColors.of(context).accent` and never hard-codes a hex.
/// Switching theme or mode rebuilds the tree — nothing else changes.
library;

import 'package:flutter/material.dart';

import '../domain/models.dart';

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

/// Mirrors `appearanceSchema.mode`.
enum ColorMode {
  system('system', 'System'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const ColorMode(this.id, this.label);
  final String id;
  final String label;

  static ColorMode fromId(String? id) =>
      values.firstWhere((mode) => mode.id == id, orElse: () => light);
}

/// Mirrors `appearanceSchema.theme`.
enum MukaiThemeId {
  mukai('mukai', 'Mukai', 'A little grounded.'),
  ocean('ocean', 'Ocean', 'Room to think.'),
  iris('iris', 'Iris', 'A different perspective.'),
  ember('ember', 'Ember', 'Keep the spark.'),
  rose('rose', 'Rose', 'A warmer kind of focus.'),
  graphite('graphite', 'Graphite', 'Quietly considered.');

  // `label`, not `name`: `Enum.name` is already taken by the value itself.
  const MukaiThemeId(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  static MukaiThemeId fromId(String? id) =>
      values.firstWhere((theme) => theme.id == id, orElse: () => ocean);
}

/// Persisted appearance choice — the same shape as `ThemePreferences`.
@immutable
class MukaiPreferences {
  const MukaiPreferences({
    this.mode = ColorMode.light,
    this.theme = MukaiThemeId.ocean,
  });

  final ColorMode mode;
  final MukaiThemeId theme;

  /// Same key the desktop app uses, so a future shared store lines up.
  static const String storageKey = 'mukai.appearance.v1';

  static const MukaiPreferences defaults = MukaiPreferences();

  MukaiPreferences copyWith({ColorMode? mode, MukaiThemeId? theme}) =>
      MukaiPreferences(mode: mode ?? this.mode, theme: theme ?? this.theme);

  Map<String, String> toJson() => {'mode': mode.id, 'theme': theme.id};

  factory MukaiPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return MukaiPreferences(
      mode: ColorMode.fromId(json['mode'] as String?),
      theme: MukaiThemeId.fromId(json['theme'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MukaiPreferences && other.mode == mode && other.theme == theme;

  @override
  int get hashCode => Object.hash(mode, theme);
}

// ---------------------------------------------------------------------------
// Palettes
// ---------------------------------------------------------------------------

/// The eight `--theme-*` variables a named theme swaps per mode.
@immutable
class AccentPalette {
  const AccentPalette({
    required this.accent,
    required this.hover,
    required this.soft,
    required this.text,
    required this.border,
    required this.rail,
    required this.nav,
    required this.glow,
  });

  final Color accent;
  final Color hover;
  final Color soft;
  final Color text;
  final Color border;
  final Color rail;
  final Color nav;
  final Color glow;

  static AccentPalette lerp(AccentPalette a, AccentPalette b, double t) =>
      AccentPalette(
        accent: Color.lerp(a.accent, b.accent, t)!,
        hover: Color.lerp(a.hover, b.hover, t)!,
        soft: Color.lerp(a.soft, b.soft, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        rail: Color.lerp(a.rail, b.rail, t)!,
        nav: Color.lerp(a.nav, b.nav, t)!,
        glow: Color.lerp(a.glow, b.glow, t)!,
      );
}

/// Neutral surfaces and text — the `tokens.css` values that stay put across
/// named themes ("Shared theme surfaces; bot identities keep their own colors").
@immutable
class NeutralPalette {
  const NeutralPalette({
    required this.ink,
    required this.textBody,
    required this.textSecondary,
    required this.textMuted,
    required this.textSoft,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.sidebar,
    required this.line,
    required this.lineStrong,
    required this.onAccent,
    required this.shadowTint,
  });

  final Color ink;
  final Color textBody;
  final Color textSecondary;
  final Color textMuted;
  final Color textSoft;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color sidebar;
  final Color line;
  final Color lineStrong;
  final Color onAccent;

  /// Base colour for the layered soft shadows in `--shadow`.
  final Color shadowTint;

  static const NeutralPalette light = NeutralPalette(
    ink: Color(0xFF263b45),
    textBody: Color(0xFF45545d),
    textSecondary: Color(0xFF68786a),
    textMuted: Color(0xFF89988b),
    textSoft: Color(0xFFa7b19f),
    surface: Color(0xFFffffff),
    surfaceRaised: Color(0xFFffffff),
    surfaceMuted: Color(0xFFf7f9f5),
    sidebar: Color(0xFFf5f6f3),
    line: Color(0xFFe9eeeb),
    lineStrong: Color(0xFFd7e0d7),
    onAccent: Color(0xFFffffff),
    shadowTint: Color(0xFF12232e),
  );

  static const NeutralPalette dark = NeutralPalette(
    ink: Color(0xFFe0e8e5),
    textBody: Color(0xFFc4d0c9),
    textSecondary: Color(0xFFacbcb3),
    textMuted: Color(0xFF8c9f95),
    textSoft: Color(0xFF72867b),
    surface: Color(0xFF1c252a),
    surfaceRaised: Color(0xFF232e34),
    surfaceMuted: Color(0xFF253036),
    sidebar: Color(0xFF192126),
    line: Color(0xFF303e43),
    lineStrong: Color(0xFF43545a),
    onAccent: Color(0xFFffffff),
    shadowTint: Color(0xFF000000),
  );

  static NeutralPalette lerp(NeutralPalette a, NeutralPalette b, double t) =>
      NeutralPalette(
        ink: Color.lerp(a.ink, b.ink, t)!,
        textBody: Color.lerp(a.textBody, b.textBody, t)!,
        textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
        textMuted: Color.lerp(a.textMuted, b.textMuted, t)!,
        textSoft: Color.lerp(a.textSoft, b.textSoft, t)!,
        surface: Color.lerp(a.surface, b.surface, t)!,
        surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, t)!,
        surfaceMuted: Color.lerp(a.surfaceMuted, b.surfaceMuted, t)!,
        sidebar: Color.lerp(a.sidebar, b.sidebar, t)!,
        line: Color.lerp(a.line, b.line, t)!,
        lineStrong: Color.lerp(a.lineStrong, b.lineStrong, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
        shadowTint: Color.lerp(a.shadowTint, b.shadowTint, t)!,
      );
}

/// One named theme, both modes — a `ThemeDefinition`.
@immutable
class MukaiThemeDefinition {
  const MukaiThemeDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.light,
    required this.dark,
  });

  final MukaiThemeId id;
  final String label;
  final String description;
  final AccentPalette light;
  final AccentPalette dark;

  AccentPalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Port of the `themes` array. Order drives the Appearance picker.
const List<MukaiThemeDefinition> kMukaiThemes = <MukaiThemeDefinition>[
  MukaiThemeDefinition(
    id: MukaiThemeId.mukai,
    label: 'Mukai',
    description: 'A little grounded.',
    light: AccentPalette(
      accent: Color(0xFF388b73),
      hover: Color(0xFF28745e),
      soft: Color(0xFFe8f2ed),
      text: Color(0xFF37725b),
      border: Color(0xFFb9d5c8),
      rail: Color(0xFFedf3f0),
      nav: Color(0xFF2b665e),
      glow: Color(0xFF65d5c5),
    ),
    dark: AccentPalette(
      accent: Color(0xFF409f84),
      hover: Color(0xFF4caf92),
      soft: Color(0xFF203b34),
      text: Color(0xFF8dcdb3),
      border: Color(0xFF365b4e),
      rail: Color(0xFF111b23),
      nav: Color(0xFF2b665e),
      glow: Color(0xFF70d7b7),
    ),
  ),
  MukaiThemeDefinition(
    id: MukaiThemeId.ocean,
    label: 'Ocean',
    description: 'Room to think.',
    light: AccentPalette(
      accent: Color(0xFF377eb0),
      hover: Color(0xFF2b6590),
      soft: Color(0xFFeaf2f9),
      text: Color(0xFF376d95),
      border: Color(0xFFb5cfe4),
      rail: Color(0xFFedf3f8),
      nav: Color(0xFF285d85),
      glow: Color(0xFF82c9f1),
    ),
    dark: AccentPalette(
      accent: Color(0xFF3b87bd),
      hover: Color(0xFF4899d1),
      soft: Color(0xFF20354a),
      text: Color(0xFF91c9ef),
      border: Color(0xFF355774),
      rail: Color(0xFF101b2b),
      nav: Color(0xFF285d85),
      glow: Color(0xFF82c9f1),
    ),
  ),
  MukaiThemeDefinition(
    id: MukaiThemeId.iris,
    label: 'Iris',
    description: 'A different perspective.',
    light: AccentPalette(
      accent: Color(0xFF8060b4),
      hover: Color(0xFF684a9b),
      soft: Color(0xFFf1edf8),
      text: Color(0xFF77549c),
      border: Color(0xFFd1c0e7),
      rail: Color(0xFFf2eef7),
      nav: Color(0xFF62467e),
      glow: Color(0xFFc5a6f2),
    ),
    dark: AccentPalette(
      accent: Color(0xFF9170c8),
      hover: Color(0xFFa181da),
      soft: Color(0xFF352941),
      text: Color(0xFFceb3f3),
      border: Color(0xFF58446d),
      rail: Color(0xFF1b1627),
      nav: Color(0xFF62467e),
      glow: Color(0xFFc5a6f2),
    ),
  ),
  MukaiThemeDefinition(
    id: MukaiThemeId.ember,
    label: 'Ember',
    description: 'Keep the spark.',
    light: AccentPalette(
      accent: Color(0xFFb87643),
      hover: Color(0xFF9a5b32),
      soft: Color(0xFFfbf0e7),
      text: Color(0xFF9b663e),
      border: Color(0xFFe9cbb3),
      rail: Color(0xFFf8f0e9),
      nav: Color(0xFF875a3b),
      glow: Color(0xFFecb283),
    ),
    dark: AccentPalette(
      accent: Color(0xFFc28a56),
      hover: Color(0xFFd39a65),
      soft: Color(0xFF3c2f27),
      text: Color(0xFFe4b587),
      border: Color(0xFF69503b),
      rail: Color(0xFF241c19),
      nav: Color(0xFF875a3b),
      glow: Color(0xFFecb283),
    ),
  ),
  MukaiThemeDefinition(
    id: MukaiThemeId.rose,
    label: 'Rose',
    description: 'A warmer kind of focus.',
    light: AccentPalette(
      accent: Color(0xFFae6581),
      hover: Color(0xFF96506b),
      soft: Color(0xFFf9edf2),
      text: Color(0xFF9a5b76),
      border: Color(0xFFe6c1d0),
      rail: Color(0xFFf7eef2),
      nav: Color(0xFF7f4a64),
      glow: Color(0xFFe6a4bf),
    ),
    dark: AccentPalette(
      accent: Color(0xFFbb7897),
      hover: Color(0xFFce8aa9),
      soft: Color(0xFF3c2a34),
      text: Color(0xFFe4aec6),
      border: Color(0xFF644353),
      rail: Color(0xFF231922),
      nav: Color(0xFF7f4a64),
      glow: Color(0xFFe6a4bf),
    ),
  ),
  MukaiThemeDefinition(
    id: MukaiThemeId.graphite,
    label: 'Graphite',
    description: 'Quietly considered.',
    light: AccentPalette(
      accent: Color(0xFF637583),
      hover: Color(0xFF4d606f),
      soft: Color(0xFFedf1f4),
      text: Color(0xFF526b7a),
      border: Color(0xFFc2cdd5),
      rail: Color(0xFFeff2f4),
      nav: Color(0xFF4d606b),
      glow: Color(0xFFb4c7d2),
    ),
    dark: AccentPalette(
      accent: Color(0xFF738a99),
      hover: Color(0xFF839daa),
      soft: Color(0xFF2c373f),
      text: Color(0xFFb5cbd8),
      border: Color(0xFF4a5b67),
      rail: Color(0xFF181e24),
      nav: Color(0xFF4d606b),
      glow: Color(0xFFb4c7d2),
    ),
  ),
];

MukaiThemeDefinition mukaiThemeOf(MukaiThemeId id) => kMukaiThemes.firstWhere(
  (theme) => theme.id == id,
  orElse: () => kMukaiThemes[1],
);

// ---------------------------------------------------------------------------
// Bot identity — `--{scout,atlas,nova}-*`
// ---------------------------------------------------------------------------

/// Per-bot colour identity. These deliberately ignore the selected theme so a
/// bot keeps its face wherever you are.
@immutable
class BotIdentityColors {
  const BotIdentityColors({
    required this.surfaceTop,
    required this.surfaceBottom,
    required this.mark,
    required this.label,
    required this.labelSurface,
    required this.border,
  });

  final Color surfaceTop;
  final Color surfaceBottom;
  final Color mark;
  final Color label;
  final Color labelSurface;
  final Color border;

  Gradient get surface => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[surfaceTop, surfaceBottom],
  );
}

/// Presentation half of [BotIdentity], which lives in the domain layer. Kept as
/// an extension so call sites read `bot.identity.colors(brightness)` while the
/// domain entity stays free of colour.
extension BotIdentityPalette on BotIdentity {
  BotIdentityColors colors(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    switch (this) {
      case BotIdentity.scout:
        return isDark
            ? const BotIdentityColors(
                surfaceTop: Color(0xFF3d3326),
                surfaceBottom: Color(0xFF453a29),
                mark: Color(0xFFe0b265),
                label: Color(0xFFe4c18a),
                labelSurface: Color(0xFF443724),
                border: Color(0xFF6b5533),
              )
            : const BotIdentityColors(
                surfaceTop: Color(0xFFfff8ea),
                surfaceBottom: Color(0xFFfff3dd),
                mark: Color(0xFFe9ad42),
                label: Color(0xFFb39964),
                labelSurface: Color(0xFFfaf5e7),
                border: Color(0xFFf0dcb4),
              );
      case BotIdentity.atlas:
        return isDark
            ? const BotIdentityColors(
                surfaceTop: Color(0xFF223c35),
                surfaceBottom: Color(0xFF284b40),
                mark: Color(0xFF4d8d74),
                label: Color(0xFFa1d9be),
                labelSurface: Color(0xFF284539),
                border: Color(0xFF3b6756),
              )
            : const BotIdentityColors(
                surfaceTop: Color(0xFFe4f4eb),
                surfaceBottom: Color(0xFFb9e8d7),
                mark: Color(0xFF2b7664),
                label: Color(0xFF75a18a),
                labelSurface: Color(0xFFeef6ef),
                border: Color(0xFFd3ecdf),
              );
      case BotIdentity.nova:
        return isDark
            ? const BotIdentityColors(
                surfaceTop: Color(0xFF332b43),
                surfaceBottom: Color(0xFF443453),
                mark: Color(0xFFb596df),
                label: Color(0xFFc9adeb),
                labelSurface: Color(0xFF3c304d),
                border: Color(0xFF614a79),
              )
            : const BotIdentityColors(
                surfaceTop: Color(0xFFeee7fc),
                surfaceBottom: Color(0xFFd8c8f4),
                mark: Color(0xFF9773c6),
                label: Color(0xFFa08ab5),
                labelSurface: Color(0xFFf3eff9),
                border: Color(0xFFe2d7f5),
              );
      case BotIdentity.mukai:
        return isDark
            ? const BotIdentityColors(
                surfaceTop: Color(0xFF20354a),
                surfaceBottom: Color(0xFF25405a),
                mark: Color(0xFF82c9f1),
                label: Color(0xFF91c9ef),
                labelSurface: Color(0xFF20354a),
                border: Color(0xFF355774),
              )
            : const BotIdentityColors(
                surfaceTop: Color(0xFFeaf2f9),
                surfaceBottom: Color(0xFFdcebf6),
                mark: Color(0xFF377eb0),
                label: Color(0xFF376d95),
                labelSurface: Color(0xFFeaf2f9),
                border: Color(0xFFb5cfe4),
              );
      case BotIdentity.neutral:
        return isDark
            ? const BotIdentityColors(
                surfaceTop: Color(0xFF362f45),
                surfaceBottom: Color(0xFF3b3450),
                mark: Color(0xFFbc9de5),
                label: Color(0xFFbc9de5),
                labelSurface: Color(0xFF362f45),
                border: Color(0xFF4d4560),
              )
            : const BotIdentityColors(
                surfaceTop: Color(0xFFf6f8f6),
                surfaceBottom: Color(0xFFeef2ee),
                mark: Color(0xFFa187c3),
                label: Color(0xFF89988b),
                labelSurface: Color(0xFFf1ebf8),
                border: Color(0xFFe2e7e2),
              );
    }
  }
}

// ---------------------------------------------------------------------------
// ThemeExtension
// ---------------------------------------------------------------------------

/// The one stop for colour. Reach it with `MukaiColors.of(context)`.
@immutable
class MukaiColors extends ThemeExtension<MukaiColors> {
  const MukaiColors({
    required this.accent,
    required this.neutral,
    required this.brightness,
    required this.themeId,
  });

  final AccentPalette accent;
  final NeutralPalette neutral;
  final Brightness brightness;
  final MukaiThemeId themeId;

  bool get isDark => brightness == Brightness.dark;

  static MukaiColors of(BuildContext context) {
    final MukaiColors? colors = Theme.of(context).extension<MukaiColors>();
    assert(colors != null, 'MukaiColors missing from ThemeData.extensions');
    return colors ??
        MukaiColors.from(MukaiPreferences.defaults, Brightness.light);
  }

  factory MukaiColors.from(MukaiPreferences prefs, Brightness brightness) {
    final MukaiThemeDefinition definition = mukaiThemeOf(prefs.theme);
    return MukaiColors(
      accent: definition.palette(brightness),
      neutral: brightness == Brightness.dark
          ? NeutralPalette.dark
          : NeutralPalette.light,
      brightness: brightness,
      themeId: prefs.theme,
    );
  }

  // Roles widgets actually ask for.

  Color get canvas => neutral.surface;

  /// Grouped/table-screen background — the app's `--sidebar` tone.
  Color get canvasGrouped => isDark ? neutral.sidebar : neutral.surfaceMuted;
  Color get card => neutral.surfaceRaised;
  Color get cardMuted => neutral.surfaceMuted;
  Color get rail => accent.rail;
  Color get ink => neutral.ink;
  Color get textBody => neutral.textBody;
  Color get textSecondary => neutral.textSecondary;
  Color get textMuted => neutral.textMuted;
  Color get textSoft => neutral.textSoft;
  Color get textOnAccent => neutral.onAccent;
  Color get hairline => neutral.line;
  Color get hairlineStrong => neutral.lineStrong;
  Color get accentColor => accent.accent;
  Color get accentPressed => accent.hover;
  Color get accentSoft => accent.soft;
  Color get accentInk => accent.text;
  Color get accentBorder => accent.border;
  Color get glow => accent.glow;
  Color get link => accent.text;

  /// Selected row / pressed fill.
  Color get pressed => accent.soft;

  /// Focus ring: accent at partial alpha, like the CSS `box-shadow`.
  Color get focusRing => accent.accent.withValues(alpha: isDark ? 0.45 : 0.32);

  /// Overlay tint for scrims behind sheets.
  Color get scrim => isDark ? const Color(0xB3000000) : const Color(0x7312232e);

  BotIdentityColors identity(BotIdentity identity) =>
      identity.colors(brightness);

  @override
  MukaiColors copyWith({
    AccentPalette? accent,
    NeutralPalette? neutral,
    Brightness? brightness,
    MukaiThemeId? themeId,
  }) => MukaiColors(
    accent: accent ?? this.accent,
    neutral: neutral ?? this.neutral,
    brightness: brightness ?? this.brightness,
    themeId: themeId ?? this.themeId,
  );

  @override
  MukaiColors lerp(covariant MukaiColors? other, double t) {
    if (other == null) return this;
    return MukaiColors(
      accent: AccentPalette.lerp(accent, other.accent, t),
      neutral: NeutralPalette.lerp(neutral, other.neutral, t),
      brightness: t < 0.5 ? brightness : other.brightness,
      themeId: t < 0.5 ? themeId : other.themeId,
    );
  }
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Holds appearance preferences and tells the tree to repaint. Persistence is
/// injected so this stays dependency-free: pass a loader/saver backed by
/// `shared_preferences` (or the Mukai backend) when we wire up real settings.
class AppearanceController extends ChangeNotifier {
  AppearanceController({MukaiPreferences? initial, this.loader, this.saver})
    : preferences = initial ?? MukaiPreferences.defaults;

  final MukaiPreferences Function()? loader;
  final Future<void> Function(MukaiPreferences)? saver;

  MukaiPreferences preferences;

  void hydrate() {
    final MukaiPreferences? stored = loader?.call();
    if (stored != null && stored != preferences) {
      preferences = stored;
      notifyListeners();
    }
  }

  void setMode(ColorMode mode) {
    if (mode == preferences.mode) return;
    preferences = preferences.copyWith(mode: mode);
    notifyListeners();
    _persist();
  }

  void setTheme(MukaiThemeId theme) {
    if (theme == preferences.theme) return;
    preferences = preferences.copyWith(theme: theme);
    notifyListeners();
    _persist();
  }

  void cycleTheme() {
    final int index = kMukaiThemes.indexWhere(
      (definition) => definition.id == preferences.theme,
    );
    final MukaiThemeDefinition next =
        kMukaiThemes[(index + 1) % kMukaiThemes.length];
    setTheme(next.id);
  }

  ThemeMode get themeMode => switch (preferences.mode) {
    ColorMode.system => ThemeMode.system,
    ColorMode.light => ThemeMode.light,
    ColorMode.dark => ThemeMode.dark,
  };

  Future<void> _persist() async {
    await saver?.call(preferences);
  }

  /// Status-bar / browser chrome colour, mirroring the `theme-color` meta tag.
  Color statusTintColor(Brightness brightness) =>
      mukaiThemeOf(preferences.theme).palette(brightness).rail;
}

/// Read the controller anywhere: `AppearanceScope.of(context)`.
class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppearanceController of(BuildContext context) {
    final AppearanceScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppearanceScope>();
    assert(scope != null, 'No AppearanceScope above this context');
    return scope!.notifier!;
  }
}
