import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/design/widgets.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/home/widgets/bot_conversation_list.dart';

const bot = MukaiBot(
  id: 'bot',
  name: 'Mukai',
  role: 'Main bot',
  mascot: 'mukai-logo',
  identity: BotIdentity.mukai,
);

Future<void> frame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  test(
    'conversation API preserves working flags and defaults older responses to idle',
    () {
      final client = MukaiApiClient('https://mukai.test', 'fixture');
      addTearDown(client.close);
      final repo = ApiRepository(client);
      expect(repo.conversationFromJson({'isWorking': true}).isWorking, isTrue);
      expect(
        repo.conversationFromJson({'isWorking': false}).isWorking,
        isFalse,
      );
      expect(repo.conversationFromJson({}).isWorking, isFalse);
    },
  );

  testWidgets(
    'busy bots replace + with dots and running chats stay visible beyond the first three',
    (tester) async {
      final chats = [
        for (var i = 0; i < 7; i++)
          Conversation(
            id: 'chat-$i',
            title: 'Conversation $i',
            botId: bot.id,
            updatedAt: DateTime(2026, 11, 4).subtract(Duration(hours: i)),
          ),
      ];
      Conversation? opened;
      MukaiBot? created;
      Widget view(Set<String> working) => MaterialApp(
        theme: mukaiTheme(MukaiPreferences.defaults, Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BotConversationList(
              bots: const [bot],
              conversations: chats,
              workingConversationIds: working,
              onOpenConversation: (chat) => opened = chat,
              onNewConversation: (bot) => created = bot,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view({'chat-6'}));
      await frame(tester);
      expect(find.byType(BouncingDots), findsOneWidget);
      expect(find.byTooltip('New conversation with Mukai'), findsNothing);
      await tester.tap(find.text('Mukai'));
      await frame(tester);
      expect(find.byType(BouncingDots), findsNWidgets(2));
      expect(find.text('Conversation 6'), findsOneWidget);
      expect(find.text('Conversation 3'), findsNothing);
      expect(find.text('Load 3 more'), findsOneWidget);
      await tester.tap(find.text('Conversation 6'));
      expect(opened?.id, 'chat-6');
      expect(created, isNull);
      await tester.pumpWidget(view({}));
      await frame(tester);
      expect(find.byType(BouncingDots), findsNothing);
      expect(find.byTooltip('New conversation with Mukai'), findsOneWidget);
      expect(find.text('Conversation 6'), findsNothing);
      await tester.tap(find.byTooltip('New conversation with Mukai'));
      expect(created, bot);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server-flagged bot chats show work on their receiving bot', (
    tester,
  ) async {
    const receiver = MukaiBot(
      id: 'receiver',
      name: 'Receiver',
      role: 'Helper',
      mascot: 'mukai-logo',
      identity: BotIdentity.mukai,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
        home: Scaffold(
          body: BotConversationList(
            bots: const [bot, receiver],
            conversations: [
              Conversation(
                id: 'pair',
                title: 'Bot pair',
                botId: bot.id,
                kind: 'bot',
                botIds: const ['bot', 'receiver'],
                isWorking: true,
                updatedAt: DateTime.now(),
              ),
            ],
            onOpenConversation: (_) {},
            onNewConversation: (_) {},
          ),
        ),
      ),
    );
    await frame(tester);
    expect(find.byTooltip('New conversation with Mukai'), findsOneWidget);
    expect(find.byTooltip('New conversation with Receiver'), findsNothing);
    expect(find.byType(BouncingDots), findsOneWidget);
    await tester.tap(find.text('Receiver'));
    await frame(tester);
    expect(find.byType(BouncingDots), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('three-dot animation respects reduced motion', (tester) async {
    Widget view(bool reduced) => MaterialApp(
      theme: mukaiTheme(MukaiPreferences.defaults, Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Scaffold(body: Center(child: BouncingDots())),
      ),
    );
    List<Offset> positions() => [
      for (final dot
          in find
              .descendant(
                of: find.byType(BouncingDots),
                matching: find.byType(DecoratedBox),
              )
              .evaluate())
        tester.getTopLeft(find.byElementPredicate((element) => element == dot)),
    ];
    await tester.pumpWidget(view(false));
    final initial = positions();
    expect(initial, hasLength(3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(positions(), isNot(initial));
    await tester.pumpWidget(view(true));
    final still = positions();
    await tester.pump(const Duration(seconds: 2));
    expect(positions(), still);
    expect(tester.takeException(), isNull);
  });
}
