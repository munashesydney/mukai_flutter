import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/home_shell.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/data/demo/demo_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/chat/chat_screen.dart';
import 'package:mukai_flutter/features/home/minimal_bot_home.dart';
import 'package:mukai_flutter/features/home/minimal_chat_home.dart';
import 'package:mukai_flutter/features/home/widgets/bot_conversation_list.dart';
import 'package:mukai_flutter/state/session_controller.dart';

const alpha = MukaiBot(
  id: 'alpha',
  name: 'Alpha',
  role: 'Builder',
  mascot: 'mukai-logo',
  identity: BotIdentity.mukai,
  isMain: true,
);
const beta = MukaiBot(
  id: 'beta',
  name: 'Beta',
  role: 'Helper',
  mascot: 'mukai-logo',
  identity: BotIdentity.mukai,
);

Future<void> tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

void main() {
  testWidgets(
    'bot groups sort recent chats, paginate independently and navigate',
    (tester) async {
      Conversation? opened;
      MukaiBot? created;
      var creationCount = 0;
      final now = DateTime.now();
      final chats = [
        for (var i = 7; i >= 0; i--)
          Conversation(
            id: 'a$i',
            title: 'Alpha chat $i',
            botId: alpha.id,
            updatedAt: now.subtract(Duration(minutes: i + 1)),
          ),
        Conversation(
          id: 'b',
          title: 'Beta chat',
          botId: beta.id,
          updatedAt: now,
        ),
        Conversation(
          id: 'pair',
          title: 'Bot pair',
          botId: alpha.id,
          kind: 'bot',
          botIds: [alpha.id, beta.id],
          updatedAt: now,
        ),
        Conversation(
          id: 'space',
          title: 'Space chat',
          botId: alpha.id,
          kind: 'space',
          updatedAt: now,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BotConversationList(
                bots: const [alpha, beta],
                conversations: chats,
                onOpenConversation: (chat) => opened = chat,
                onNewConversation: (bot) {
                  created = bot;
                  creationCount++;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Alpha chat 0'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Beta')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );
      await tester.tap(find.text('Alpha'));
      await tick(tester);
      for (var i = 0; i < 3; i++) {
        expect(find.text('Alpha chat $i'), findsOneWidget);
      }
      expect(find.text('Alpha chat 3'), findsNothing);
      expect(find.text('Space chat'), findsNothing);
      await tester.tap(find.text('Load 3 more'));
      await tick(tester);
      expect(find.text('Alpha chat 5'), findsOneWidget);
      expect(find.text('Alpha chat 6'), findsNothing);
      await tester.ensureVisible(find.text('Load 2 more'));
      await tester.tap(find.text('Load 2 more'));
      await tick(tester);
      expect(find.text('Alpha chat 7'), findsOneWidget);
      expect(find.textContaining('Load '), findsNothing);
      await tester.tap(find.text('Alpha chat 0'));
      expect(opened?.id, 'a0');
      await tester.tap(find.text('Alpha'));
      await tick(tester);
      expect(find.text('Alpha chat 0'), findsNothing);
      await tester.tap(find.text('Beta'));
      await tick(tester);
      expect(find.text('Beta chat'), findsOneWidget);
      expect(find.text('Bot pair'), findsOneWidget);
      expect(find.text('Alpha chat 0'), findsNothing);
      await tester.tap(find.byTooltip('New conversation with Beta'));
      await tick(tester);
      expect(created, beta);
      expect(creationCount, 1);
      expect(find.text('Beta chat'), findsOneWidget);
      expect(find.text('Bot pair'), findsOneWidget);
      await tester.tap(find.byTooltip('New conversation with Alpha'));
      await tick(tester);
      expect(created, alpha);
      expect(creationCount, 2);
      expect(find.text('Alpha chat 0'), findsNothing);
      expect(find.text('Beta chat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty bot can expand and start a conversation at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: mukaiTheme(MukaiPreferences.defaults, Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: BotConversationList(
                bots: const [alpha],
                conversations: const [],
                onOpenConversation: (_) {},
                onNewConversation: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Alpha'));
      await tick(tester);
      expect(find.text('No conversations yet.'), findsOneWidget);
      expect(find.textContaining('Load '), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('appearance toggle swaps landing page and sidebar label live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearance = AppearanceController();
    final session = SessionController(
      MukaiDemoRepository(latency: Duration.zero),
    );
    unawaited(session.loadRecents());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      appearance.dispose();
    });
    await tester.pumpWidget(
      MukaiScope(
        appearance: appearance,
        session: session,
        child: MaterialApp(
          theme: mukaiTheme(appearance.preferences, Brightness.light),
          home: const HomeShell(),
        ),
      ),
    );
    await tick(tester);
    expect(session.recents, hasLength(6));
    expect(session.botConversations, hasLength(9));
    // Minimalism on: the landing page is the chat itself, ready to type.
    expect(find.byType(MinimalChatHome), findsOneWidget);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('A little momentum.'), findsNothing);
    await tester.tap(find.byTooltip('Open sidebar'));
    await tick(tester);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Bots'), findsNothing);
    expect(find.text('Workspace'), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tick(tester);
    await tester.tap(find.text('Theme'));
    await tick(tester);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.tap(find.text('Minimalism'));
    await tick(tester);
    expect(appearance.preferences.minimalism, isFalse);
    await tester.drag(find.text('Appearance').last, const Offset(0, 650));
    await tick(tester);
    await tester.tap(find.byTooltip('Open sidebar'));
    await tick(tester);
    expect(find.text('Bots'), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
    await tester.tap(find.text('Bots'));
    await tick(tester);
    expect(find.byType(MinimalBotHome), findsOneWidget);
    expect(find.byType(MinimalChatHome), findsNothing);
    expect(find.text('A little momentum.'), findsNothing);
    await tester.tap(find.byTooltip('Open sidebar'));
    await tick(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tick(tester);
    await tester.tap(find.text('Theme'));
    await tick(tester);
    await tester.tap(find.text('Minimalism'));
    await tick(tester);
    expect(appearance.preferences.minimalism, isTrue);
    await tester.drag(find.text('Appearance').last, const Offset(0, 650));
    await tick(tester);
    await tester.tap(find.byTooltip('Open sidebar'));
    await tick(tester);
    expect(find.text('Chat'), findsOneWidget);
    await tester.tap(find.text('Chat'));
    await tick(tester);
    expect(find.byType(MinimalChatHome), findsOneWidget);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
