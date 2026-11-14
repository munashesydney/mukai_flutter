import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/home_shell.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/data/demo/demo_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/design/widgets.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/chat/chat_screen.dart';
import 'package:mukai_flutter/features/chat/widgets/activity_sheet.dart';
import 'package:mukai_flutter/state/session_controller.dart';

Future<SessionController> _openWorkspace(
  WidgetTester tester, {
  double width = 402,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 2622);
  // Preserve the real iPhone status area in these layout regressions.
  tester.view.viewPadding = const FakeViewPadding(top: 186, bottom: 102);
  tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);

  final appearance = AppearanceController(
    initial: const MukaiPreferences(minimalism: false),
  );
  final session = SessionController(
    MukaiDemoRepository(
      latency: Duration.zero,
      streamCadence: const Duration(milliseconds: 1),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    appearance.dispose();
  });
  unawaited(session.loadRecents());
  await tester.pumpWidget(
    MukaiScope(
      appearance: appearance,
      session: session,
      child: MaterialApp(
        theme: mukaiTheme(appearance.preferences, Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const HomeShell(),
      ),
    ),
  );
  await _tick(tester);
  return session;
}

// The workspace status indicator animates continuously, so settle would never
// finish. Advance bounded frames instead.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

Future<void> _selectDestination(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open sidebar'));
  await _tick(tester);
  await tester.tap(
    label == 'Settings' ? find.byTooltip('Settings') : find.text(label).last,
  );
  await _tick(tester);
}

void main() {
  testWidgets('compact phone supports larger text across workspace and chat', (
    tester,
  ) async {
    String? layoutDetails;
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      layoutDetails = details.toString();
      oldHandler!(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
    await _openWorkspace(tester, width: 320, textScale: 1.3);
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutDetails);
    await tester.scrollUntilVisible(
      find.text('Nova'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nova'));
    await _tick(tester);
    await tester.tap(find.text('Project notes cleanup').hitTestable().last);
    await _tick(tester);
    expect(tester.takeException(), isNull);
    final field = find.widgetWithText(TextField, 'Message Nova…');
    await tester.tap(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 1014);
    tester.view.padding = const FakeViewPadding(top: 186);
    await _tick(tester);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(
      tester.getBottomRight(find.byTooltip('Send message')).dy,
      lessThanOrEqualTo(536),
    );
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    tester.testTextInput.hide();
    await _tick(tester);
    await _selectDestination(tester, 'Bots');
    expect(tester.takeException(), isNull, reason: layoutDetails);
    await tester.tap(find.byTooltip('Appearance'));
    await _tick(tester);
    expect(find.byType(SheetGrabber), findsOneWidget);
    expect(tester.takeException(), isNull, reason: layoutDetails);
  });

  testWidgets(
    'sidebar replaces bottom navigation and reaches each destination',
    (tester) async {
      await _openWorkspace(tester);
      expect(find.byTooltip('Appearance'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester.getTopLeft(find.byTooltip('Open sidebar')).dy,
        greaterThanOrEqualTo(62),
      );

      for (final label in <String>['Pursuits', 'Spaces', 'Tools', 'Settings']) {
        await _selectDestination(tester, label);
        expect(find.text(label), findsWidgets);
        expect(find.byTooltip('Appearance'), findsNothing);
        expect(tester.takeException(), isNull);
      }

      await _selectDestination(tester, 'Bots');
      expect(find.byTooltip('Appearance'), findsOneWidget);
      expect(find.text('Scout'), findsOneWidget);
      expect(find.text('Atlas'), findsOneWidget);
      expect(find.text('Nova'), findsOneWidget);
    },
  );

  testWidgets(
    'sidebar pushes a rounded page and keeps its floating controls fixed',
    (tester) async {
      await _openWorkspace(tester);
      final page = find.byKey(const ValueKey('main-page-canvas'));
      expect(tester.getTopLeft(page).dx, 0);
      await tester.tap(find.byTooltip('Open sidebar'));
      await _tick(tester);
      expect(tester.getTopLeft(page).dx, closeTo(402 * .8, .5));
      expect(tester.getSize(page).width, 402);
      expect(
        (tester.widget<ClipRRect>(page).borderRadius as BorderRadius).topLeft.x,
        42,
      );
      final header = tester.getRect(find.byTooltip('Search workspace'));
      final newChat = tester.getRect(find.text('New chat'));
      final settings = tester.getRect(find.byTooltip('Settings'));
      final scroll = find.descendant(
        of: find.byKey(const PageStorageKey('sidebar-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.drag(scroll, const Offset(0, -420));
      await _tick(tester);
      expect(tester.getRect(find.byTooltip('Search workspace')), header);
      expect(tester.getRect(find.text('New chat')), newChat);
      expect(tester.getRect(find.byTooltip('Settings')), settings);
      await tester.tapAt(const Offset(385, 400));
      await _tick(tester);
      expect(tester.getTopLeft(page).dx, 0);
      expect(tester.widget<ClipRRect>(page).borderRadius, BorderRadius.zero);
      final swipe = await tester.startGesture(const Offset(140, 400));
      await swipe.moveBy(const Offset(25, 0));
      await swipe.moveBy(const Offset(90, 0));
      await tester.pump();
      final partialOffset = tester.getTopLeft(page).dx;
      expect(partialOffset, greaterThan(0));
      await swipe.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(tester.getTopLeft(page).dx, greaterThan(partialOffset));
      await swipe.moveBy(const Offset(100, 0));
      await swipe.up();
      await _tick(tester);
      expect(find.byTooltip('Search workspace').hitTestable(), findsOneWidget);
      await tester.dragFrom(const Offset(190, 400), const Offset(-250, 0));
      await _tick(tester);
      expect(tester.getTopLeft(page).dx, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chat remains tappable below the status area and above keyboard',
    (tester) async {
      final session = await _openWorkspace(tester);
      await tester.ensureVisible(find.text('Nova'));
      await tester.tap(find.text('Nova'));
      await _tick(tester);
      await tester.tap(find.text('Project notes cleanup').hitTestable().last);
      await _tick(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(session.bot.id, 'nova');
      expect(
        tester.getTopLeft(find.byTooltip('Open sidebar')).dy,
        greaterThanOrEqualTo(62),
      );

      final field = find.widgetWithText(TextField, 'Message Nova…');
      await tester.tap(field);
      await tester.pump();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 1014);
      tester.view.padding = const FakeViewPadding(top: 186);
      await _tick(tester);
      const keyboardTop = (2622 - 1014) / 3;
      expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(keyboardTop));
      expect(
        tester.getBottomRight(find.byTooltip('Send message')).dy,
        lessThanOrEqualTo(keyboardTop),
      );

      const message = 'Help me plan tomorrow.';
      await tester.enterText(field, message);
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await _tick(tester);
      expect(
        session.thread
            .where((turn) => turn.fromUser)
            .any(
              (turn) => turn.blocks.whereType<TextBlock>().any(
                (block) => block.text == message,
              ),
            ),
        isTrue,
      );
      expect(find.text('Approval needed'), findsOneWidget);
      await tester.ensureVisible(find.text('Decline'));
      await tester.tap(find.text('Decline'));
      await _tick(tester);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = const FakeViewPadding();
      tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
      tester.testTextInput.hide();
      await _tick(tester);
      await tester.tap(find.byTooltip('Activity'));
      await _tick(tester);
      expect(find.byType(ActivitySheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ActivitySheet),
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsNothing,
      );
      await tester.drag(find.text('Activity').last, const Offset(0, 600));
      await _tick(tester);
      expect(find.byType(ActivitySheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace sheet dismisses by dragging its content down', (
    tester,
  ) async {
    await _openWorkspace(tester);
    await tester.tap(find.byTooltip('Open sidebar'));
    await _tick(tester);
    await tester.tap(find.byTooltip('Switch workspace'));
    await _tick(tester);
    expect(find.text('Your workspaces'), findsOneWidget);
    await tester.drag(find.text('Your workspaces'), const Offset(0, 650));
    await _tick(tester);
    expect(find.text('Your workspaces'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar selects conversations and keeps the most recently opened first',
    (tester) async {
      final session = await _openWorkspace(tester);
      final sidebar = find.byKey(const PageStorageKey('sidebar-scroll'));
      Finder row(String id) => find.byKey(ValueKey('sidebar-conversation-$id'));
      ListTile tile(String id) => tester.widget<ListTile>(
        find.descendant(of: row(id), matching: find.byType(ListTile)),
      );
      Future<void> openSidebar() async {
        await tester.tap(find.byTooltip('Open sidebar'));
        await _tick(tester);
      }

      Future<void> selectChat(String id) async {
        await tester.scrollUntilVisible(
          row(id),
          150,
          scrollable: find.descendant(
            of: sidebar,
            matching: find.byType(Scrollable),
          ),
        );
        await _tick(tester);
        await tester.tap(row(id));
        await _tick(tester);
      }

      await openSidebar();
      expect(find.text('Companions'), findsNothing);
      expect(find.text('Conversations'), findsOneWidget);
      expect(
        find.descendant(of: sidebar, matching: find.text('Scout')),
        findsNothing,
      );
      await selectChat('scout-week');
      expect(session.conversationId, 'scout-week');
      await openSidebar();
      expect(session.sidebarConversations.first.id, 'scout-week');
      expect(tile('scout-week').selected, isTrue);
      expect(row('scout-week').hitTestable(), findsOneWidget);
      await selectChat('scout-notes');
      expect(session.conversationId, 'scout-notes');
      await openSidebar();
      expect(session.sidebarConversations.take(2).map((c) => c.id), [
        'scout-notes',
        'scout-week',
      ]);
      expect(tile('scout-notes').selected, isTrue);
      expect(tile('scout-week').selected, isFalse);
      expect(
        tester.getTopLeft(row('scout-notes')).dy,
        lessThan(tester.getTopLeft(row('scout-week')).dy),
      );
      await tester.tap(find.text('Bots').last);
      await _tick(tester);
      await openSidebar();
      expect(tile('scout-notes').selected, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sidebar shows and clears running dots on the correct conversation',
    (tester) async {
      final session = await _openWorkspace(tester);
      session.aiActivity = {
        'running': [
          {
            'workspaceId': session.workspace.id,
            'conversationId': 'scout-today',
            'botId': 'scout',
          },
          {
            'workspaceId': 'another-workspace',
            'conversationId': 'nova-today',
            'botId': 'nova',
          },
        ],
      };
      unawaited(session.loadRecents());
      await _tick(tester);
      await tester.tap(find.byTooltip('Open sidebar'));
      await _tick(tester);
      Finder indicator(String id) => find.descendant(
        of: find.byKey(ValueKey('sidebar-conversation-$id')),
        matching: find.byType(BouncingDots),
      );
      expect(indicator('scout-today'), findsOneWidget);
      expect(indicator('nova-today'), findsNothing);
      session.aiActivity = {};
      unawaited(session.loadRecents());
      await _tick(tester);
      expect(indicator('scout-today'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('appearance sheet grabber is horizontally centered', (
    tester,
  ) async {
    await _openWorkspace(tester);
    await tester.tap(find.byTooltip('Appearance'));
    await _tick(tester);

    final handle = find.descendant(
      of: find.byType(SheetGrabber),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.maxWidth == 36 &&
            widget.constraints?.maxHeight == 5,
      ),
    );
    expect(handle, findsOneWidget);
    expect(tester.getCenter(handle).dx, closeTo(201, 0.5));
    expect(find.text('Appearance'), findsWidgets);
    expect(find.byTooltip('Close appearance'), findsNothing);
    await tester.drag(find.text('Appearance').last, const Offset(0, 650));
    await _tick(tester);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
