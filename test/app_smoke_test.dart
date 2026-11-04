/// End-to-end widget tests: the app is driven the way a person drives it —
/// type, tap, wait — from connection through to the workspace.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/app.dart';
import 'package:mukai_flutter/core/settings_store.dart';
import 'package:mukai_flutter/data/demo/demo_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/widgets.dart';
import 'package:mukai_flutter/state/session_controller.dart';

/// A running client plus the pieces a test needs to poke.
///
/// Two conventions worth knowing before editing:
///   * [tick] is used instead of `pumpAndSettle` everywhere. The status pill
///     breathes and the "is working" dots bounce on infinite loops, so a settle
///     would spin until the test timed out.
///   * The surface is sized like an iPhone. These layouts are designed for a
///     phone; the 800x600 test default would report overflow on screens that
///     are fine on device.
class _Client {
  _Client._(this.tester, this.appearance, this.session, this.store);

  final WidgetTester tester;
  final AppearanceController appearance;
  final SessionController session;
  final MemorySettingsStore store;

  static Future<_Client> open(
    WidgetTester tester, {
    MukaiPreferences? saved,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 at 3x
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final MemorySettingsStore store = MemorySettingsStore();
    if (saved != null) {
      await store.write(MukaiPreferences.storageKey, saved.toJson());
    }

    final _Client client = _Client._(
      tester,
      AppearanceController(
        loader: () =>
            MukaiPreferences.fromJson(store.read(MukaiPreferences.storageKey)),
        saver: (MukaiPreferences preferences) =>
            store.write(MukaiPreferences.storageKey, preferences.toJson()),
      ),
      // No artificial latency, and a reply that streams block-per-millisecond
      // so a finished answer lands inside a test's patience.
      SessionController(
        MukaiDemoRepository(
          latency: Duration.zero,
          streamCadence: const Duration(milliseconds: 1),
        ),
      ),
      store,
    );

    await tester.pumpWidget(
      MukaiApp(appearance: client.appearance, session: client.session),
    );
    await client.tick(150);
    return client;
  }

  /// Advance the fake clock, flushing timers and animations.
  Future<void> tick([int milliseconds = 400]) =>
      tester.pump(Duration(milliseconds: milliseconds));
}

void main() {
  testWidgets('opens with server URL before asking for account credentials', (
    WidgetTester tester,
  ) async {
    await _Client.open(tester);

    expect(find.text('A little possibility.\nA little Mukai.'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Mukai token'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('Using Cloudflare Zero Trust?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.controller!.text, isEmpty);
    }
    expect(find.text('Setup code'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(
      tester
          .widget<MukaiButton>(find.widgetWithText(MukaiButton, 'Connect'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('server connection leads to account sign-in then workspace', (
    WidgetTester tester,
  ) async {
    final client = await _Client.open(tester);
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await client.tick(500);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await client.tick(500);
    expect(find.text('A little momentum.'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    expect(find.text('Setup code'), findsNothing);
    expect(find.text('Wake Mukai'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password is obscured and can be revealed', (tester) async {
    await _Client.open(tester);
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pump();
    final token = find.byType(TextField).last;
    expect(tester.widget<TextField>(token).obscureText, isTrue);
    await tester.enterText(token, 'test-password');
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(token).obscureText, isFalse);
    expect(tester.widget<TextField>(token).controller!.text, 'test-password');
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<TextField>(token).obscureText, isTrue);
  });

  testWidgets('a saved theme and mode come back on the next launch', (
    WidgetTester tester,
  ) async {
    const MukaiPreferences saved = MukaiPreferences(
      mode: ColorMode.dark,
      theme: MukaiThemeId.rose,
    );
    final _Client client = await _Client.open(tester, saved: saved);

    expect(client.appearance.preferences, saved);
    expect(client.appearance.themeMode, ThemeMode.dark);

    final MukaiColors colors = MukaiColors.of(
      tester.element(find.text('A little possibility.\nA little Mukai.')),
    );
    expect(colors.isDark, isTrue);
    expect(colors.canvas, const Color(0xFF1C252A));
    expect(colors.accentColor, const Color(0xFFBB7897)); // rose, dark ramp
  });
}
