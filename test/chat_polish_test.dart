import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/home_shell.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/core/approval_presentation.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';
import 'package:mukai_flutter/data/demo/demo_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/chat/chat_screen.dart';
import 'package:mukai_flutter/features/chat/widgets/approval_dock.dart';
import 'package:mukai_flutter/features/chat/widgets/chat_blocks.dart';
import 'package:mukai_flutter/features/chat/widgets/composer.dart';
import 'package:mukai_flutter/features/chat/widgets/message_bubble.dart';
import 'package:mukai_flutter/state/session_controller.dart';

Future<void> frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<SessionController> open(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final appearance = AppearanceController();
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
  await tester.pumpWidget(
    MukaiScope(
      session: session,
      appearance: appearance,
      child: MaterialApp(
        theme: mukaiTheme(appearance.preferences, Brightness.light),
        home: child,
      ),
    ),
  );
  await frames(tester);
  return session;
}

void main() {
  test('explicit approval questions do not append duplicated JSON', () {
    final api = MukaiApiClient('http://localhost:3000', 'test');
    addTearDown(api.close);
    final repository = ApiRepository(api);
    final block = repository.approvalFromJson({
      'id': 'a1',
      'toolName': 'communicate',
      'ask': {'action': 'approval', 'question': 'Publish this report?'},
      'input': {'action': 'approval', 'question': 'Publish this report?'},
    });
    expect(block.reason, 'Publish this report?');
    final details = approvalDetails({
      'command': 'echo hello',
      'api_key': 'do-not-show',
      'nested': {'password': 'private'},
    });
    expect(details, contains('Command: echo hello'));
    expect(details, isNot(contains('do-not-show')));
    expect(details, isNot(contains('private')));
    expect(details, contains('[redacted]'));
  });

  testWidgets(
    'tool details stay collapsed and preserve a user expansion while streaming',
    (tester) async {
      Widget view(ToolState state) => MaterialApp(
        theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
        home: Scaffold(
          body: ChatBlockView(
            block: ToolBlock(
              id: 'same-tool',
              label: 'Reading files',
              detail: 'Private tool details',
              state: state,
            ),
            bots: const [],
          ),
        ),
      );
      await tester.pumpWidget(view(ToolState.running));
      await frames(tester);
      expect(find.text('Private tool details'), findsNothing);
      await tester.tap(find.text('Reading files'));
      await frames(tester);
      expect(find.text('Private tool details'), findsOneWidget);
      await tester.pumpWidget(view(ToolState.done));
      await tester.pump();
      expect(find.text('Private tool details'), findsOneWidget);
      await tester.tap(find.text('Reading files'));
      await frames(tester);
      expect(find.text('Private tool details'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming text updates in place without reentering a transition',
    (tester) async {
      Widget view(String value) => MaterialApp(
        theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
        home: Scaffold(
          body: MessageView(
            message: ChatMessage(
              id: 'message-one',
              fromUser: false,
              at: DateTime(2026),
              botId: 'mukai',
              blocks: [TextBlock(value, id: 'text-one')],
              streaming: true,
            ),
            bots: const [],
          ),
        ),
      );
      await tester.pumpWidget(view('Hello'));
      await tester.pump();
      final first = tester.element(
        find.byKey(const ValueKey('TextBlock-text-one')),
      );
      await tester.pumpWidget(view('Hello, a little more text.'));
      await tester.pump();
      expect(
        tester.element(find.byKey(const ValueKey('TextBlock-text-one'))),
        same(first),
      );
      expect(
        find.textContaining('a little more text', findRichText: true),
        findsWidgets,
      );
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'approval occupies the composer and restores its unsent draft after a decision',
    (tester) async {
      const bot = MukaiBot(
        id: 'scout',
        name: 'Scout',
        role: 'Main',
        mascot: 'mukai-logo',
        identity: BotIdentity.scout,
      );
      final session = await open(tester, const ChatScreen(bot: bot));
      await tester.enterText(find.byType(TextField).first, 'Keep this draft');
      unawaited(session.send('Save a summary'));
      await frames(tester, 16);
      expect(find.byType(ApprovalDock), findsOneWidget);
      expect(find.byType(MukaiComposer), findsNothing);
      expect(find.text('Approval needed'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await frames(tester);
      expect(find.byType(ApprovalDock), findsNothing);
      expect(find.byType(MukaiComposer), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Keep this draft',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'denial reasons preserve a canceled draft and resolve the request',
    (tester) async {
      const bot = MukaiBot(
        id: 'scout',
        name: 'Scout',
        role: 'Main',
        mascot: 'mukai-logo',
        identity: BotIdentity.scout,
      );
      final session = await open(tester, const ChatScreen(bot: bot));
      unawaited(session.send('Save a summary'));
      await frames(tester, 16);
      await tester.tap(find.text('Deny with reason'));
      await frames(tester);
      await tester.enterText(
        find.byType(TextFormField),
        '  Please save a draft first.  ',
      );
      await tester.tap(find.text('Cancel'));
      await frames(tester);
      expect(find.text('Approve'), findsOneWidget);
      await tester.tap(find.text('Deny with reason'));
      await frames(tester);
      expect(find.text('  Please save a draft first.  '), findsOneWidget);
      await tester.tap(find.text('Send denial'));
      await frames(tester);
      expect(find.byType(ApprovalDock), findsNothing);
      expect(
        session.thread
            .expand((m) => m.blocks)
            .whereType<ToolBlock>()
            .any(
              (b) =>
                  b.detail == 'Please save a draft first.' &&
                  b.state == ToolState.error,
            ),
        isTrue,
      );
      expect(find.byType(MukaiComposer), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new chat focuses its composer and model picker has no sparkle', (
    tester,
  ) async {
    await open(tester, const HomeShell());
    await tester.tap(find.byTooltip('New chat'));
    await frames(tester);
    await tester.ensureVisible(find.text('Nova').last);
    await tester.tap(find.text('Nova').last);
    await frames(tester, 16);
    final field = find.byType(TextField).first;
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    final composer = find.byType(MukaiComposer);
    expect(
      find.descendant(
        of: composer,
        matching: find.byIcon(Icons.auto_awesome_outlined),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('fresh composer requests focus when its server load enables it', (
    tester,
  ) async {
    Widget view(bool enabled) => MaterialApp(
      theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
      home: Scaffold(
        body: MukaiComposer(
          autofocus: true,
          enabled: enabled,
          botName: 'Mukai',
          responding: false,
          onSend: (_) {},
          onStop: () {},
        ),
      ),
    );
    await tester.pumpWidget(view(false));
    await frames(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isFalse,
    );
    await tester.pumpWidget(view(true));
    await frames(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'multiple requests preserve answer drafts and fit above the keyboard',
    (tester) async {
      await open(
        tester,
        const Scaffold(
          body: Column(
            children: [
              Expanded(child: SizedBox()),
              ApprovalDock(
                requests: [
                  ApprovalBlock(
                    id: 'question-one',
                    toolName: 'communicate',
                    reason: 'Which audience?',
                    fullAccessAvailable: false,
                    ask: {
                      'action': 'clarification',
                      'question': 'Which audience?',
                    },
                  ),
                  ApprovalBlock(
                    id: 'question-two',
                    toolName: 'communicate',
                    reason: 'Publish this?',
                    fullAccessAvailable: false,
                    ask: {'action': 'approval', 'question': 'Publish this?'},
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 1014);
      await frames(tester);
      await tester.enterText(find.byType(TextField), 'The design team');
      expect(tester.getBottomRight(find.text('Send answer')).dy, lessThan(536));
      await tester.tap(find.byTooltip('Next request'));
      await frames(tester);
      expect(find.text('Publish this?'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous request'));
      await frames(tester);
      expect(find.text('The design team'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
