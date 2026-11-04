import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/core/format.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/design/disclosure.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/chat/widgets/file_preview.dart';
import 'package:mukai_flutter/features/chat/widgets/message_bubble.dart';
import 'package:mukai_flutter/features/chat/widgets/ai_queue_notice.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 7; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Widget app(Widget child) => MaterialApp(
  theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  test(
    'duration matches desktop hours, minutes, seconds and unknown dates',
    () {
      final start = DateTime(2026);
      expect(
        Format.workDuration(start, start.add(const Duration(seconds: 63))),
        '1m 3s',
      );
      expect(
        Format.workDuration(start, start.add(const Duration(seconds: 3664))),
        '1h 1m 4s',
      );
      expect(Format.workDuration(null, start), isNull);
      expect(
        Format.workDuration(start, start.subtract(const Duration(seconds: 1))),
        isNull,
      );
    },
  );

  test('saved compaction and image parts retain the desktop semantics', () {
    final client = MukaiApiClient('https://mukai.test', 'fixture');
    addTearDown(client.close);
    final repo = ApiRepository(client);
    ChatMessage read(String status) => repo.messageFromJson({
      'id': 'm',
      'role': 'assistant',
      'status': status,
      'parts': [
        {
          'id': 'compact',
          'type': 'compaction',
          'state': 'compacting',
          'tokensBefore': 64000,
        },
        {'id': 't', 'type': 'tool', 'activityId': 'a'},
      ],
      'activity': [
        {
          'id': 'a',
          'tool': 'media',
          'action': 'view_image',
          'status': 'complete',
        },
      ],
    }, 'history');
    expect(
      read('streaming').blocks.whereType<CompactionBlock>().single.state,
      'compacting',
    );
    expect(
      read('interrupted').blocks.whereType<CompactionBlock>().single.state,
      'interrupted',
    );
    expect(
      read('complete').blocks.whereType<ToolBlock>().single.previewHref,
      'mukai-activity:a',
    );
    expect(read('complete').conversationId, 'history');
  });

  testWidgets(
    'memory cooldown counts down and clears when the scheduler recovers',
    (tester) async {
      final activity = {
        'running': [],
        'queued': [
          {
            'conversationId': 'history',
            'memoryPressure': {
              'cooldownUntil': DateTime.now()
                  .add(const Duration(seconds: 8))
                  .toIso8601String(),
              'providerName': 'Local model',
              'effectiveLimit': 1,
              'configuredLimit': 3,
            },
          },
        ],
      };
      await tester.pumpWidget(
        app(AIQueueNotice(activity: activity, conversationId: 'history')),
      );
      expect(find.text('Waiting for memory recovery'), findsOneWidget);
      expect(find.textContaining('Retry in'), findsOneWidget);
      expect(find.textContaining('saved maximum is 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(
        app(
          const AIQueueNotice(
            activity: {'running': [], 'queued': []},
            conversationId: 'history',
          ),
        ),
      );
      expect(find.text('Waiting for memory recovery'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overall work stays closed as calls arrive and final answer remains visible',
    (tester) async {
      final client = MukaiApiClient('https://mukai.test', 'fixture');
      addTearDown(client.close);
      final repo = ApiRepository(client);
      ChatMessage message(String status) => repo.messageFromJson({
        'id': 'response',
        'botId': 'bot',
        'role': 'assistant',
        'status': status,
        'createdAt': '2026-11-03T10:00:00Z',
        'startedAt': '2026-11-03T10:00:00Z',
        'finishedAt': status == 'complete' ? '2026-11-03T10:01:03Z' : null,
        'parts': [
          {
            'id': 'comment',
            'type': 'text',
            'text': 'I will inspect the workspace.',
          },
          {'id': 'tool-part', 'type': 'tool', 'activityId': 'tool-call'},
          if (status == 'complete')
            {
              'id': 'answer',
              'type': 'text',
              'text': 'Here is the final answer.',
            },
        ],
        'activity': [
          {
            'id': 'tool-call',
            'tool': 'file_operations',
            'action': 'read_file',
            'summary': 'Read launch notes',
            'status': status == 'complete' ? 'complete' : 'running',
          },
        ],
      }, 'history');
      await tester.pumpWidget(
        app(MessageView(message: message('streaming'), bots: const [])),
      );
      await frames(tester);
      expect(find.textContaining('Working for'), findsOneWidget);
      expect(
        find.textContaining('inspect the workspace', findRichText: true),
        findsNothing,
      );
      await tester.pumpWidget(
        app(MessageView(message: message('complete'), bots: const [])),
      );
      await frames(tester);
      expect(find.text('Worked for 1m 3s'), findsOneWidget);
      expect(
        find.textContaining('final answer', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('inspect the workspace', findRichText: true),
        findsNothing,
      );
      await tester.tap(find.text('Worked for 1m 3s'));
      await frames(tester);
      expect(
        find.textContaining('inspect the workspace', findRichText: true),
        findsWidgets,
      );
      // The desktop hierarchy: the work disclosure wraps a second-level
      // group describing the run, which wraps the individual tool.
      expect(find.text('Read files'), findsOneWidget);
      expect(find.text('Read a file'), findsNothing);
      await tester.tap(find.text('Read files'));
      await frames(tester);
      expect(find.text('Read a file'), findsOneWidget);
      expect(find.textContaining('Read launch notes'), findsNothing);
      await tester.tap(find.text('Read a file'));
      await frames(tester);
      expect(find.textContaining('Read launch notes'), findsWidgets);
      await tester.tap(find.text('Worked for 1m 3s'));
      await frames(tester);
      expect(find.text('Read files'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'whitespace commentary never splits a tool loop and images only open on tap',
    (tester) async {
      final client = MukaiApiClient('https://mukai.test', 'fixture');
      addTearDown(client.close);
      final repo = ApiRepository(client);
      final message = repo.messageFromJson({
        'id': 'loop',
        'botId': 'bot',
        'role': 'assistant',
        'status': 'complete',
        'createdAt': '2026-11-03T10:00:00Z',
        'startedAt': '2026-11-03T10:00:00Z',
        'finishedAt': '2026-11-03T10:01:03Z',
        'parts': [
          {'id': 't1', 'type': 'tool', 'activityId': 'cmd1'},
          {'id': 'nl', 'type': 'text', 'text': ' \n '},
          {'id': 't2', 'type': 'tool', 'activityId': 'cmd2'},
          {'id': 't3', 'type': 'tool', 'activityId': 'img1'},
          {'id': 't4', 'type': 'tool', 'activityId': 'img2'},
          {'id': 't5', 'type': 'tool', 'activityId': 'cmd3'},
          {'id': 'answer', 'type': 'text', 'text': 'Here is the final answer.'},
        ],
        'activity': [
          {
            'id': 'cmd1',
            'tool': 'terminal',
            'action': 'run',
            'status': 'complete',
          },
          {
            'id': 'cmd2',
            'tool': 'terminal',
            'action': 'run',
            'status': 'complete',
          },
          {
            'id': 'img1',
            'tool': 'media',
            'action': 'view_image',
            'status': 'complete',
          },
          {
            'id': 'img2',
            'tool': 'media',
            'action': 'view_image',
            'status': 'complete',
          },
          {
            'id': 'cmd3',
            'tool': 'terminal',
            'action': 'run',
            'status': 'complete',
          },
        ],
      }, 'history');
      await tester.pumpWidget(
        app(MessageView(message: message, bots: const [])),
      );
      await frames(tester);
      await tester.tap(find.text('Worked for 1m 3s'));
      await frames(tester);
      // The whitespace commentary between the commands is not a boundary: the
      // first loop merges into one group, the images form their own run,
      // and only the image break starts a third command group.
      expect(find.text('Ran commands'), findsNWidgets(2));
      expect(find.text('Viewed 2 images'), findsOneWidget);
      expect(find.text('View image'), findsNothing);
      await tester.tap(find.text('Ran commands').first);
      await frames(tester);
      expect(find.text('Ran a command'), findsNWidgets(2));
      await tester.tap(find.text('Viewed 2 images'));
      await frames(tester);
      // Desktop keeps the picture out of the transcript: image rows are
      // buttons that open the preview on demand.
      expect(find.text('View image'), findsNWidgets(2));
      expect(find.byType(ChatImagePreview), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a running call shimmers the outer label, then the collapsed group, then the tool',
    (tester) async {
      final client = MukaiApiClient('https://mukai.test', 'fixture');
      addTearDown(client.close);
      final repo = ApiRepository(client);
      ChatMessage message(String status) => repo.messageFromJson({
        'id': 'shimmer',
        'botId': 'bot',
        'role': 'assistant',
        'status': status,
        'createdAt': '2026-11-03T10:00:00Z',
        'startedAt': '2026-11-03T10:00:00Z',
        'finishedAt': status == 'complete' ? '2026-11-03T10:01:03Z' : null,
        'parts': [
          {'id': 'tool-part', 'type': 'tool', 'activityId': 'tool-call'},
          if (status == 'complete') ...[
            {'id': 'answer', 'type': 'text', 'text': 'Here is the answer.'},
          ],
        ],
        'activity': [
          {
            'id': 'tool-call',
            'tool': 'file_operations',
            'action': 'read_file',
            'summary': 'Read launch notes',
            'status': status == 'complete' ? 'complete' : 'running',
          },
        ],
      }, 'history');
      await tester.pumpWidget(
        app(MessageView(message: message('streaming'), bots: const [])),
      );
      await frames(tester);
      // Everything collapsed: the hidden tool passes its shimmer up to the
      // only visible description of the work, "Working for …".
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(
        find.ancestor(
          of: find.textContaining('Working for'),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
      // Opening the outer transcript hands the shimmer to the still-collapsed
      // group label (the live label of an active run is its running tool).
      await tester.tap(find.textContaining('Working for'));
      await frames(tester);
      expect(
        find.ancestor(
          of: find.textContaining('Working for'),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Reading a file'),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
      // Opening the group lets the individual tool row wear its own shimmer.
      await tester.tap(find.text('Reading a file'));
      await frames(tester);
      expect(find.text('Reading a file'), findsNWidgets(2));
      expect(
        find.ancestor(
          of: find.text('Reading a file').first,
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.text('Reading a file').last,
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
      expect(find.byType(ShaderMask), findsOneWidget);
      // Finished work never shimmers anywhere.
      await tester.pumpWidget(
        app(MessageView(message: message('complete'), bots: const [])),
      );
      await frames(tester);
      expect(find.text('Worked for 1m 3s'), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disclosure reveals height progressively and keeps its child safely mounted',
    (tester) async {
      await tester.pumpWidget(
        app(
          Column(
            children: [
              MukaiDisclosure(
                title: const Text('Details'),
                builder: (_) =>
                    const SizedBox(height: 200, child: Text('Body')),
              ),
            ],
          ),
        ),
      );
      expect(find.text('Body'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pump();
      final expansion = find.byType(MukaiExpansion);
      expect(tester.getSize(expansion).height, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(expansion).height, inExclusiveRange(0, 200));
      await frames(tester);
      expect(tester.getSize(expansion).height, 200);
      await tester.tap(find.text('Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(expansion).height, inExclusiveRange(0, 200));
      await frames(tester);
      expect(find.text('Body'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening a disclosure in the reversed chat list keeps its header in place',
    (tester) async {
      await tester.pumpWidget(
        app(
          ListView(
            reverse: true,
            children: [
              const SizedBox(height: 240),
              MukaiDisclosure(
                title: const Text('Worked'),
                builder: (_) =>
                    const SizedBox(height: 220, child: Text('Work body')),
              ),
              const SizedBox(height: 400),
            ],
          ),
        ),
      );
      await frames(tester);
      final before = tester.getTopLeft(find.text('Worked')).dy;
      await tester.tap(find.text('Worked'));
      await frames(tester);
      expect(find.text('Work body'), findsOneWidget);
      expect(
        (tester.getTopLeft(find.text('Worked')).dy - before).abs(),
        lessThan(1),
      );
      await tester.tap(find.text('Worked'));
      await frames(tester);
      expect(
        (tester.getTopLeft(find.text('Worked')).dy - before).abs(),
        lessThan(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compaction stays inside the work dropdown as a desktop divider',
    (tester) async {
      ChatMessage message(String state) => ChatMessage(
        id: 'compaction',
        fromUser: false,
        at: DateTime.now(),
        streaming: state == 'compacting',
        blocks: [
          const TextBlock('Before compaction', commentary: true),
          CompactionBlock(
            id: 'c',
            state: state,
            before: 64000,
            after: state == 'complete' ? 16000 : null,
          ),
          const TextBlock('After compaction', commentary: true),
          if (state != 'compacting') const TextBlock('Final answer'),
        ],
      );
      await tester.pumpWidget(
        app(MessageView(message: message('compacting'), bots: const [])),
      );
      await frames(tester);
      expect(find.text('Compacting context…'), findsNothing);
      await tester.tap(find.textContaining('Working'));
      await frames(tester);
      expect(find.text('Compacting context…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(
        app(MessageView(message: message('complete'), bots: const [])),
      );
      await frames(tester);
      expect(find.text('Context compacted'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Divider), findsNWidgets(2));
      expect(
        find.byTooltip(
          '64000 → 16000 estimated context tokens. Original messages are kept.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Before compaction')).dy,
        lessThan(tester.getTopLeft(find.text('Context compacted')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Context compacted')).dy,
        lessThan(tester.getTopLeft(find.text('After compaction')).dy),
      );
      await tester.tap(find.text('Worked'));
      await frames(tester);
      expect(find.text('Context compacted'), findsNothing);
      expect(find.text('Final answer'), findsOneWidget);
      await tester.tap(find.text('Worked'));
      await frames(tester);
      expect(find.text('Context compacted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed and interrupted compactions remain inside a compact transcript',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final state in ['failed', 'interrupted']) {
        final label = 'Context compaction $state';
        await tester.pumpWidget(
          app(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: MessageView(
                key: ValueKey(state),
                message: ChatMessage(
                  id: state,
                  fromUser: false,
                  at: DateTime.now(),
                  blocks: [
                    CompactionBlock(id: state, state: state, before: 64000),
                  ],
                ),
                bots: const [],
              ),
            ),
          ),
        );
        await frames(tester);
        expect(find.text(label), findsNothing);
        await tester.tap(find.text('Worked'));
        await frames(tester);
        expect(find.text(label), findsOneWidget);
        expect(find.byType(Divider), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Worked'));
        await frames(tester);
        expect(find.text(label), findsNothing);
      }
    },
  );

  testWidgets(
    'RAM recovery uses scheduler state and never shows another conversation notice',
    (tester) async {
      final activity = {
        'running': [
          {
            'conversationId': 'history',
            'memoryRetry': {'attempt': 2, 'maxAttempts': 3, 'phase': 'retry'},
          },
        ],
        'queued': [],
      };
      await tester.pumpWidget(
        app(AIQueueNotice(activity: activity, conversationId: 'other')),
      );
      expect(find.text('Retrying after memory rejection'), findsNothing);
      await tester.pumpWidget(
        app(AIQueueNotice(activity: activity, conversationId: 'history')),
      );
      expect(find.text('Retrying after memory rejection'), findsOneWidget);
      expect(find.textContaining('Retry 2/3'), findsOneWidget);
      expect(find.text('Continuing from saved results.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
