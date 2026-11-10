import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/core/message_reference.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';
import 'package:mukai_flutter/data/demo/demo_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/chat/widgets/chat_blocks.dart';
import 'package:mukai_flutter/features/chat/widgets/composer.dart';
import 'package:mukai_flutter/features/chat/widgets/reference_preview.dart';
import 'package:mukai_flutter/state/session_controller.dart';

void main() {
  testWidgets(
    'active replies accept a queued draft and prevent duplicate sends',
    (tester) async {
      var sent = '';
      Widget view(bool submitting) => MaterialApp(
        theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
        home: Scaffold(
          body: MukaiComposer(
            botName: 'Mukai',
            responding: true,
            allowQueue: true,
            submitting: submitting,
            onSend: (text) => sent = text,
            onStop: () {},
          ),
        ),
      );
      await tester.pumpWidget(view(false));
      await tester.enterText(find.byType(TextField), 'Focus on mobile.');
      await tester.pump();
      expect(find.byTooltip('Queue follow-up'), findsOneWidget);
      await tester.tap(find.byTooltip('Queue follow-up'));
      await tester.pump();
      expect(sent, 'Focus on mobile.');
      await tester.pumpWidget(view(true));
      await tester.enterText(find.byType(TextField), 'Another thought.');
      await tester.pump();
      expect(find.byTooltip('Queue follow-up'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('desktop references round trip with blank lines and nested quotes', () {
    const reference = MessageReference(
      label: 'Scout: review',
      text: 'First line\n\n> Nested quote',
    );
    final parsed = splitMessageReference(reference.format('Focus here.'));
    expect(parsed.text, 'Focus here.');
    expect(parsed.reference!.text, reference.text);
    expect(parsed.reference!.label, reference.label);
    expect(
      splitMessageReference(
        'Regarding the layout:\nKeep it compact.',
      ).reference,
      isNull,
    );
  });

  test('saved steering parts preserve their identity and attachments', () {
    final api = MukaiApiClient('https://fixture.test', 'fixture');
    addTearDown(api.close);
    final message = ApiRepository(api).messageFromJson({
      'id': 'reply',
      'role': 'assistant',
      'parts': [
        {
          'id': 'steer-1',
          'type': 'steering',
          'text': 'Use mobile.',
          'attachments': [
            {'id': 'file-1', 'name': 'notes.txt'},
          ],
        },
      ],
    }, 'chat');
    final steer = message.blocks.whereType<SteeringBlock>().single;
    expect(steer.stableId, 'steer-1');
    expect(steer.isProcess, isTrue);
    expect(steer.attachments.single.url, 'mukai-attachment:file-1');
  });

  testWidgets('selected message text can be added as a reference', (
    tester,
  ) async {
    final session = SessionController(MukaiDemoRepository());
    final appearance = AppearanceController();
    addTearDown(session.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MukaiScope(
        session: session,
        appearance: appearance,
        child: MaterialApp(
          theme: mukaiTheme(appearance.preferences, Brightness.light),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(30),
              child: ChatBlockView(
                block: TextBlock('Quote this sentence to ask about it.'),
                bots: [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(
      find
          .text('Quote this sentence to ask about it.', findRichText: true)
          .first,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Ask ${session.bot.name}'));
    await tester.pump();
    expect(session.reference, isNotNull);
    expect(session.reference!.text.trim(), isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a reference stays compact and opens its full text on tap', (
    tester,
  ) async {
    final text = List.filled(80, 'Full quoted context.').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: ReferencePreview(
                reference: MessageReference(label: 'Source', text: text),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ReferencePreview)).height, lessThan(160));
    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
