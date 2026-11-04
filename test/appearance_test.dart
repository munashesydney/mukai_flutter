import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/domain/models.dart';

void main() {
  testWidgets(
    'native switches paint the selected accent in light and dark themes',
    (tester) async {
      final boundaryKey = GlobalKey();
      for (final brightness in Brightness.values) {
        for (final accent in MukaiThemeId.values) {
          final preferences = MukaiPreferences(theme: accent);
          final colors = MukaiColors.from(preferences, brightness);
          await tester.pumpWidget(
            MaterialApp(
              theme: mukaiTheme(
                preferences,
                brightness,
              ).copyWith(platform: TargetPlatform.iOS),
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: Switch.adaptive(value: true, onChanged: (_) {}),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            image.dispose();
            return data!;
          });
          final argb = colors.accentColor.toARGB32();
          var tintedPixels = 0;
          for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
            if (bytes.getUint8(i) == ((argb >> 16) & 255) &&
                bytes.getUint8(i + 1) == ((argb >> 8) & 255) &&
                bytes.getUint8(i + 2) == (argb & 255)) {
              tintedPixels++;
            }
          }
          expect(
            tintedPixels,
            greaterThan(100),
            reason:
                '${accent.label} $brightness must tint the native switch track.',
          );
        }
      }
    },
  );

  group('preferences', () {
    test('defaults match the web client', () {
      expect(MukaiPreferences.defaults.mode, ColorMode.light);
      expect(MukaiPreferences.defaults.theme, MukaiThemeId.ocean);
    });

    test('round-trips through json', () {
      const MukaiPreferences prefs = MukaiPreferences(
        mode: ColorMode.dark,
        theme: MukaiThemeId.iris,
      );
      expect(MukaiPreferences.fromJson(prefs.toJson()), prefs);
    });

    test('falls back to defaults on missing or unknown values', () {
      expect(MukaiPreferences.fromJson(null), MukaiPreferences.defaults);
      expect(
        MukaiPreferences.fromJson(<String, dynamic>{
          'mode': 'twilight',
          'theme': 'chartreuse',
        }),
        MukaiPreferences.defaults,
      );
    });

    test('uses the same storage key as the desktop app', () {
      expect(MukaiPreferences.storageKey, 'mukai.appearance.v1');
    });
  });

  group('tokens', () {
    test('the six themes are present in picker order', () {
      expect(
        kMukaiThemes.map((MukaiThemeDefinition t) => t.id.id).toList(),
        <String>['mukai', 'ocean', 'iris', 'ember', 'rose', 'graphite'],
      );
    });

    test('ocean light carries the values from tokens.css', () {
      final MukaiColors colors = MukaiColors.from(
        MukaiPreferences.defaults,
        Brightness.light,
      );
      expect(colors.accentColor, const Color(0xFF377EB0));
      expect(colors.accentPressed, const Color(0xFF2B6590));
      expect(colors.accentSoft, const Color(0xFFEAF2F9));
      expect(colors.ink, const Color(0xFF263B45));
      expect(colors.canvas, const Color(0xFFFFFFFF));
      expect(colors.hairline, const Color(0xFFE9EEEB));
    });

    test('dark mode swaps the neutral ramp and keeps the accent family', () {
      final MukaiColors dark = MukaiColors.from(
        MukaiPreferences.defaults,
        Brightness.dark,
      );
      expect(dark.isDark, isTrue);
      expect(dark.canvas, const Color(0xFF1C252A));
      expect(dark.ink, const Color(0xFFE0E8E5));
      expect(dark.accentColor, const Color(0xFF3B87BD));
    });

    test('unknown theme ids resolve to ocean', () {
      expect(mukaiThemeOf(MukaiThemeId.ocean).label, 'Ocean');
      expect(MukaiThemeId.fromId('nope'), MukaiThemeId.ocean);
      expect(ColorMode.fromId('nope'), ColorMode.light);
    });

    test('lerping to t = 1 lands on the other theme', () {
      final MukaiColors ocean = MukaiColors.from(
        const MukaiPreferences(theme: MukaiThemeId.ocean),
        Brightness.light,
      );
      final MukaiColors iris = MukaiColors.from(
        const MukaiPreferences(theme: MukaiThemeId.iris),
        Brightness.light,
      );
      final MukaiColors midway = ocean.lerp(iris, 1);
      expect(midway.accentColor, iris.accentColor);
      expect(midway.themeId, MukaiThemeId.iris);
    });

    test('bot identities ignore the selected theme', () {
      final MukaiColors ocean = MukaiColors.from(
        const MukaiPreferences(theme: MukaiThemeId.ocean),
        Brightness.light,
      );
      final MukaiColors rose = MukaiColors.from(
        const MukaiPreferences(theme: MukaiThemeId.rose),
        Brightness.light,
      );
      expect(
        ocean.identity(BotIdentity.scout).mark,
        rose.identity(BotIdentity.scout).mark,
      );
      expect(ocean.identity(BotIdentity.scout).mark, const Color(0xFFE9AD42));
    });
  });

  group('AppearanceController', () {
    test('notifies on change, persists, and ignores no-ops', () async {
      final List<MukaiPreferences> saved = <MukaiPreferences>[];
      final AppearanceController controller = AppearanceController(
        saver: (MukaiPreferences prefs) async => saved.add(prefs),
      );

      int notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.themeMode, ThemeMode.light);
      controller.setMode(ColorMode.dark);
      controller.setTheme(MukaiThemeId.ember);
      controller.setTheme(MukaiThemeId.ember); // no change, no write

      await Future<void>.delayed(Duration.zero);

      expect(notifications, 2);
      expect(saved, hasLength(2));
      expect(saved.last.theme, MukaiThemeId.ember);
      expect(controller.themeMode, ThemeMode.dark);
      expect(
        controller.statusTintColor(Brightness.light),
        mukaiThemeOf(MukaiThemeId.ember).light.rail,
      );
    });

    test('cycleTheme walks the list and wraps around', () {
      final AppearanceController controller = AppearanceController(
        initial: const MukaiPreferences(theme: MukaiThemeId.graphite),
      );
      controller.cycleTheme();
      expect(controller.preferences.theme, MukaiThemeId.mukai);
    });

    test('system mode follows the platform', () {
      final AppearanceController controller = AppearanceController();
      controller.setMode(ColorMode.system);
      expect(controller.themeMode, ThemeMode.system);
    });

    test('hydrate reads what the store holds', () {
      final AppearanceController controller = AppearanceController(
        loader: () => const MukaiPreferences(
          mode: ColorMode.dark,
          theme: MukaiThemeId.mukai,
        ),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.hydrate();
      expect(controller.preferences.theme, MukaiThemeId.mukai);
      expect(notifications, 1);
    });
  });
}
