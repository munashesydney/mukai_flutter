import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/core/push_notifications.dart';
import 'package:mukai_flutter/features/chat/chat_screen.dart';
import 'package:mukai_flutter/app/home_shell.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/design/widgets.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/connected/connected_features_screen.dart';
import 'package:mukai_flutter/features/connected/connected_settings_screen.dart';
import 'package:mukai_flutter/features/connected/connected_widgets.dart';
import 'package:mukai_flutter/state/session_controller.dart';
import 'package:mukai_flutter/features/search/workspace_search.dart';

class _Server {
  late final HttpServer server;
  Future<void> Function()? cleanup;
  final requests = <({String method, String path, dynamic body})>[];
  String pursuitStatus = 'active';
  String objective = 'Ship a useful idea';
  final runs = <Map<String, dynamic>>[];
  final runQueries = <String?>[];
  String approvalMode = 'ask-for-approval';
  final providers = <Map<String, dynamic>>[];
  final assignments = <Map<String, dynamic>>[];
  final notifications = <Map<String, dynamic>>[];
  final notificationOffsets = <int>[];
  final profile = <String, dynamic>{
    'mode': 'icon',
    'letter': 'U',
    'icon': 'user',
    'background': '#b28a66',
  };
  Map<String, dynamic> get pursuit => <String, dynamic>{
    'id': 'p1',
    'workspaceId': 'w',
    'ownerBotId': 'scout',
    'name': 'Launch a small thing',
    'objective': objective,
    'successCriteria': 'It works',
    'status': pursuitStatus,
    'currentRunId': null,
    'nextRunAt': null,
    'nextRunReason': '',
    'deadline': null,
  };
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      final body = text.isEmpty ? null : jsonDecode(text);
      requests.add((
        method: request.method,
        path: request.uri.path,
        body: body,
      ));
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer test-token') {
        request.response.statusCode = 401;
        request.response.write('{"error":"Unauthorized"}');
        await request.response.close();
        return;
      }
      dynamic result;
      switch (request.uri.path) {
        case '/api/workspaces':
          result = <dynamic>[
            {
              'id': 'w',
              'name': 'Studio',
              'computer': 'local',
              'folder': '/workspace',
            },
          ];
        case '/api/bots':
          result = <dynamic>[
            {
              'id': 'scout',
              'workspaceId': 'w',
              'name': 'Scout',
              'role': 'Main Bot/Orchestrator',
              'isMain': true,
              'avatar': 'muka-mascot-2-blue',
            },
          ];
        case '/api/conversations':
          result = request.method == 'POST'
              ? <String, dynamic>{
                  'id': 's1',
                  'workspaceId': 'w',
                  'kind': 'space',
                  'name': body['name'],
                  'description': body['description'],
                  'botIds': body['botIds'],
                  'ownerBotId': null,
                  'updatedAt': '2026-11-03T00:00:00Z',
                }
              : <dynamic>[];
        case '/api/notifications':
          final offset = int.parse(
            request.uri.queryParameters['offset'] ?? '0',
          );
          notificationOffsets.add(offset);
          result = {
            'items': notifications.skip(offset).take(30).toList(),
            'total': notifications.length,
            'unread': notifications.where((n) => n['readAt'] == null).length,
          };
        case '/api/providers':
          if (request.method == 'POST') {
            final provider = <String, dynamic>{
              ...Map<String, dynamic>.from(body as Map),
              'id': 'pv',
              'hasKey': true,
            };
            providers.add(provider);
            result = provider;
          } else {
            result = providers;
          }
        case '/api/approvals':
          if (request.method == 'PUT') approvalMode = body['mode'] as String;
          result = <String, dynamic>{
            'mode': approvalMode,
            'pending': <dynamic>[],
          };
        case '/api/settings/profile':
          if (request.method == 'PUT') {
            profile.addAll(Map<String, dynamic>.from(body as Map));
          }
          result = profile;
        case '/api/pursuits':
          result = <dynamic>[pursuit];
        case '/api/pursuits/p1':
          result = <String, dynamic>{'pursuit': pursuit, 'runs': runs};
        case '/api/pursuits/p1/run':
          runQueries.add(request.uri.queryParameters['runId']);
          result = runs.firstWhere(
            (run) => run['id'] == request.uri.queryParameters['runId'],
          );
        case '/api/conversations/run-chat':
          result = {
            'id': 'run-chat',
            'workspaceId': 'w',
            'kind': 'pursuit_run',
            'ownerBotId': 'scout',
            'name': 'Background pursuit',
            'botIds': ['scout'],
            'updatedAt': '2026-11-03T00:00:00Z',
          };
        case '/api/conversations/run-chat/messages':
          result = <dynamic>[
            {
              'id': 'run-message',
              'role': 'assistant',
              'botId': 'scout',
              'content': 'Run conversation landed.',
              'createdAt': '2026-11-03T10:00:00Z',
            },
          ];
        case '/api/pursuits/p1/status':
          pursuitStatus = body['status'] as String;
          result = pursuit;
        case '/api/pursuits/p1/workpad':
          result = <String, dynamic>{
            'entries': <dynamic>[],
            'total': 0,
            'nextOffset': null,
          };
        case '/api/tools':
          result = <dynamic>[
            {
              'id': 'file_operations',
              'name': 'Files',
              'description': 'Read and write workspace files',
              'scope': 'selected-bots',
              'available': true,
              'actions': <String>['read', 'write'],
              'counts': <String, dynamic>{},
            },
          ];
        case '/api/tools/assignments':
          if (request.method == 'PUT') {
            final assignment = Map<String, dynamic>.from(body as Map);
            assignments.add(assignment);
            result = assignment;
          } else {
            result = assignments;
          }
        default:
          if (request.uri.path.startsWith('/api/notifications/')) {
            final id = request.uri.pathSegments[2],
                action = request.uri.pathSegments.last;
            if (id == 'dismiss-all') {
              notifications.clear();
            } else if (action == 'dismiss') {
              notifications.removeWhere((n) => n['id'] == id);
            } else if (action == 'read') {
              notifications.firstWhere((n) => n['id'] == id)['readAt'] =
                  '2026-11-03T00:00:00Z';
            }
            result = action == 'continue'
                ? {
                    'id': 'update-chat',
                    'kind': 'private',
                    'ownerBotId': 'scout',
                    'name': 'Follow up',
                    'updatedAt': '2026-11-03T00:00:00Z',
                  }
                : {'ok': true};
          } else {
            result = <dynamic>[];
          }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
  }
}

Future<void> _frames(WidgetTester tester) async {
  // Let real loopback IO complete outside the widget test's fake clock.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<_Server> _open(
  WidgetTester tester,
  Widget child, {
  void Function(_Server)? configure,
}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previous = HttpOverrides.current;
  HttpOverrides.global = null;
  final server = _Server();
  configure?.call(server);
  await tester.runAsync(server.start);
  final api = MukaiApiClient(
    'http://127.0.0.1:${server.server.port}',
    'test-token',
  );
  final repository = ApiRepository(api);
  await tester.runAsync(repository.refresh);
  final session = SessionController(repository);
  final appearance = AppearanceController();
  var cleaned = false;
  server.cleanup = () async {
    if (cleaned) return;
    cleaned = true;
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    appearance.dispose();
    api.close();
    await tester.runAsync(() => server.server.close(force: true));
    HttpOverrides.global = previous;
  };
  addTearDown(() async => server.cleanup!());
  await tester.pumpWidget(
    MukaiScope(
      session: session,
      appearance: appearance,
      child: MaterialApp(
        theme: mukaiTheme(appearance.preferences, Brightness.light),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
  await _frames(tester);
  return server;
}

void main() {
  testWidgets(
    'push tap opens a pursuit conversation absent from recent chat lists',
    (tester) async {
      final server = await _open(
        tester,
        const HomeShell(pushTarget: PushTarget('w', 'run-chat', 'scout')),
      );
      await _frames(tester);
      expect(
        server.requests.any((r) => r.path == '/api/conversations/run-chat'),
        true,
      );
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        tester.widget<ChatScreen>(find.byType(ChatScreen)).conversationId,
        'run-chat',
      );
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );
  testWidgets(
    'Updates appears with its inbox count and disappears once the inbox is empty',
    (tester) async {
      final server = await _open(
        tester,
        const HomeShell(),
        configure: (server) {
          server.notifications.add({'id': 'n1', 'readAt': null});
        },
      );
      final session = MukaiScope.sessionOf(
        tester.element(find.byType(HomeShell)),
      );
      await tester.runAsync(session.refreshNotices);
      await _frames(tester);
      await tester.tap(find.byTooltip('Open sidebar'));
      await _frames(tester);
      expect(find.text('Updates'), findsOneWidget);
      expect(session.updateCount, 1);
      expect(find.text('1'), findsOneWidget);
      server.notifications.clear();
      await tester.runAsync(session.refreshNotices);
      await _frames(tester);
      expect(find.text('Updates'), findsNothing);
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );

  testWidgets(
    'empty spaces stay centered in the available page and can refresh',
    (tester) async {
      final server = await _open(
        tester,
        ConnectedFeaturesScreen(kind: 'spaces', onOpenConversation: (_) {}),
      );
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final header = tester.getRect(find.byType(ConnectedHeading));
      final empty = find.byType(ConnectedEmpty);
      final icon = tester.getRect(
        find.descendant(of: empty, matching: find.byType(Icon)),
      );
      final body = tester.getRect(
        find.text(
          'Create a space to bring conversations and companions together.',
        ),
      );
      final contentCenter = (icon.top + body.bottom) / 2;
      expect(
        contentCenter,
        closeTo((header.bottom + viewport.bottom - 24) / 2, 2),
      );
      final requests = server.requests
          .where((r) => r.path == '/api/conversations')
          .length;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await tester.pump(const Duration(seconds: 1));
      await _frames(tester);
      expect(
        server.requests.where((r) => r.path == '/api/conversations').length,
        greaterThan(requests),
      );
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );

  testWidgets(
    'pursuits mirror server state and pause without creating a goal',
    (tester) async {
      final server = await _open(
        tester,
        ConnectedFeaturesScreen(kind: 'pursuits', onOpenConversation: (_) {}),
      );
      expect(find.text('Launch a small thing'), findsOneWidget);
      await tester.tap(find.text('Launch a small thing'));
      await _frames(tester);
      expect(find.text('Run now'), findsNothing);
      await tester.tap(find.byTooltip('Pursuit options'));
      await _frames(tester);
      await tester.tap(find.text('Pause'));
      await _frames(tester);
      expect(server.pursuitStatus, 'paused');
      expect(
        server.requests.any(
          (request) =>
              request.method == 'PUT' &&
              request.path == '/api/pursuits/p1/status' &&
              request.body['status'] == 'paused',
        ),
        isTrue,
      );
      expect(
        server.requests.any(
          (request) =>
              request.method == 'POST' && request.path == '/api/pursuits',
        ),
        isFalse,
      );
      await tester.tap(find.byTooltip('Pursuit options'));
      await _frames(tester);
      expect(find.text('Resume'), findsOneWidget);
      await tester.tapAt(const Offset(30, 500));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );

  testWidgets(
    'long pursuits and runs remain compact; a run opens its messages and full summary',
    (tester) async {
      Conversation? opened;
      const runId = 'a8d9c85e-9c9f-48be-a06a-8487c4648225';
      final huge = List.filled(
        180,
        'A detailed report with decisions, instructions, and useful next steps.',
      ).join(' ');
      final server = await _open(
        tester,
        ConnectedFeaturesScreen(
          kind: 'pursuits',
          onOpenConversation: (value) => opened = value,
        ),
        configure: (server) {
          server.objective = huge;
          server.runs.add({
            'id': runId,
            'status': 'complete',
            'trigger': 'schedule',
            'summary': huge,
            'conversationId': 'run-chat',
            'startedAt': '2026-11-03T10:00:00Z',
            'snapshot': server.pursuit,
          });
        },
      );
      final listCard = find.ancestor(
        of: find.text('Launch a small thing'),
        matching: find.byType(MukaiCard),
      );
      expect(tester.getSize(listCard).height, lessThan(300));
      await tester.tap(find.text('Launch a small thing'));
      await _frames(tester);
      expect(find.text('Workpad').hitTestable(), findsOneWidget);
      for (final title in ['Full objective', 'Success criteria']) {
        await tester.ensureVisible(find.text(title));
        await tester.pump();
        await tester.tap(find.text(title));
        await _frames(tester);
        // A polling refresh must preserve the expanded reader.
        await tester.pump(const Duration(seconds: 6));
        await _frames(tester);
        await tester.ensureVisible(find.text(title));
        await tester.pump();
        await tester.tap(find.text(title));
        await _frames(tester);
        expect(tester.takeException(), isNull);
      }

      final run = find.byKey(const ValueKey('pursuit-run-$runId'));
      await tester.ensureVisible(run);
      await tester.pump();
      expect(tester.getSize(run).height, lessThan(220));
      await tester.tap(run);
      await _frames(tester);
      expect(server.runQueries, contains(runId));
      expect(find.text('Pursuit run'), findsOneWidget);
      expect(
        find.textContaining('Run conversation landed.', findRichText: true),
        findsWidgets,
      );
      expect(find.text('Open conversation').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Summary'));
      await _frames(tester);
      expect(
        find.textContaining('A detailed report', findRichText: true),
        findsWidgets,
      );
      await tester.tap(find.text('Open conversation'));
      await _frames(tester);
      expect(opened?.id, 'run-chat');
      expect(opened?.kind, 'pursuit_run');
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );

  testWidgets(
    'workspace search filters real endpoint results and returns a destination',
    (tester) async {
      WorkspaceSearchResult? selected;
      final server = await _open(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await Navigator.push(
                context,
                MaterialPageRoute<WorkspaceSearchResult>(
                  builder: (_) => const WorkspaceSearchPage(),
                ),
              );
            },
            child: const Text('Find something'),
          ),
        ),
      );
      await tester.tap(find.text('Find something'));
      await _frames(tester);
      final input = find.byKey(const ValueKey('workspace-search-input'));
      expect(tester.widget<TextField>(input).autofocus, isTrue);
      await tester.enterText(input, 'small useful');
      await _frames(tester);
      expect(find.text('Launch a small thing'), findsOneWidget);
      await tester.tap(find.text('Chats'));
      await _frames(tester);
      expect(
        find.text('No matches. Try another name or word.'),
        findsOneWidget,
      );
      await tester.drag(find.byType(ChoiceChip).first, const Offset(-280, 0));
      await _frames(tester);
      await tester.tap(find.text('Pursuits'));
      await _frames(tester);
      await tester.tap(find.text('Launch a small thing'));
      await _frames(tester);
      expect(selected?.id, 'p1');
      expect(selected?.kind, WorkspaceSearchKind.pursuit);
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );

  testWidgets(
    'updates paginate, expand, mark read, continue and confirm bulk dismissal',
    (tester) async {
      Conversation? opened;
      final server = await _open(
        tester,
        UpdatesScreen(onOpenConversation: (c) => opened = c),
        configure: (server) {
          for (var i = 0; i < 31; i++) {
            server.notifications.add({
              'id': 'n$i',
              'botId': 'scout',
              'botName': 'Scout',
              'title': 'Finding $i',
              'message': '**A useful result** from autonomous work.',
              'sourceKind': 'pursuit_run',
              'createdAt': '2026-11-03T10:00:00Z',
              'readAt': null,
              'conversationId': null,
            });
          }
        },
      );
      await tester.tap(find.text('Finding 0'));
      await _frames(tester);
      expect(
        find.textContaining('A useful result', findRichText: true),
        findsWidgets,
      );
      await tester.tap(find.text('Mark read'));
      await _frames(tester);
      expect(server.notifications.first['readAt'], isNotNull);
      await tester.tap(find.text('Continue in chat'));
      await _frames(tester);
      expect(opened?.id, 'update-chat');
      await tester.scrollUntilVisible(
        find.text('Load more updates'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Load more updates'));
      await _frames(tester);
      expect(server.notificationOffsets, contains(30));
      await tester.scrollUntilVisible(
        find.byTooltip('Update options'),
        -700,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byTooltip('Update options'));
      await tester.pump();
      await tester.tap(find.byTooltip('Update options'));
      await _frames(tester);
      await tester.tap(find.text('Dismiss all'));
      await _frames(tester);
      await tester.tap(find.text('Cancel'));
      await _frames(tester);
      expect(server.notifications, hasLength(31));
      await tester.ensureVisible(find.byTooltip('Update options'));
      await tester.pump();
      await tester.tap(find.byTooltip('Update options'));
      await _frames(tester);
      await tester.tap(find.text('Dismiss all'));
      await _frames(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Dismiss all'));
      await _frames(tester);
      expect(server.notifications, isEmpty);
      expect(find.text('You’re all caught up'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );

  testWidgets('disconnect requires an explicit confirmation', (tester) async {
    var disconnected = false;
    final server = await _open(
      tester,
      ConnectedSettingsScreen(onDisconnect: () => disconnected = true),
    );
    await tester.scrollUntilVisible(
      find.text('Disconnect this iPhone'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Disconnect this iPhone'));
    await _frames(tester);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    expect(disconnected, isFalse);
    await tester.tap(find.text('Disconnect this iPhone'));
    await _frames(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Disconnect'));
    await _frames(tester);
    expect(disconnected, isTrue);
    expect(tester.takeException(), isNull);
    await server.cleanup!();
  });

  testWidgets('space creation sends React contract and opens returned space', (
    tester,
  ) async {
    Conversation? opened;
    final server = await _open(
      tester,
      ConnectedFeaturesScreen(
        kind: 'spaces',
        onOpenConversation: (conversation) => opened = conversation,
      ),
    );
    await tester.tap(find.byTooltip('New space'));
    await _frames(tester);
    await tester.enterText(find.byType(TextField).first, 'Little ideas');
    await tester.enterText(
      find.byType(TextField).at(1),
      'A place to make things',
    );
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.ensureVisible(find.text('Create space'));
    await tester.tap(find.text('Create space'));
    await _frames(tester);
    final request = server.requests.firstWhere(
      (request) =>
          request.method == 'POST' && request.path == '/api/conversations',
    );
    expect(request.body, <String, dynamic>{
      'workspaceId': 'w',
      'name': 'Little ideas',
      'description': 'A place to make things',
      'botIds': <String>['scout'],
    });
    expect(opened?.id, 's1');
    expect(opened?.kind, 'space');
    expect(tester.takeException(), isNull);
    await server.cleanup!();
  });

  testWidgets(
    'settings write approval and profile to backend while appearance stays local',
    (tester) async {
      final server = await _open(
        tester,
        ConnectedSettingsScreen(onDisconnect: () {}),
      );
      expect(find.text('Request approvals'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile).first);
      await _frames(tester);
      expect(server.approvalMode, 'full-access');
      await tester.tap(find.text('Profile'));
      await _frames(tester);
      final colorField = find.widgetWithText(TextField, 'Background color');
      await tester.enterText(colorField, '#123456');
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await _frames(tester);
      expect(server.profile['background'], '#123456');
      await tester.tap(find.text('Appearance'));
      await _frames(tester);
      expect(find.byType(SheetGrabber), findsOneWidget);
      expect(
        server.requests.any(
          (request) => request.path == '/api/settings/appearance',
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await server.cleanup!();
    },
  );
  testWidgets('provider settings save through the shared provider API', (
    tester,
  ) async {
    final server = await _open(
      tester,
      ConnectedSettingsScreen(onDisconnect: () {}),
    );
    await tester.ensureVisible(find.text('Add provider'));
    await tester.tap(find.text('Add provider'));
    await _frames(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'My provider',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'https://api.example/v1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Default model'),
      'test-model',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'API key'),
      'fixture-provider-key',
    );
    await tester.ensureVisible(find.text('Save provider'));
    await tester.tap(find.text('Save provider'));
    await _frames(tester);
    expect(server.providers.single['name'], 'My provider');
    expect(server.providers.single['kind'], 'openai');
    expect(server.providers.single['defaultModel'], 'test-model');
    expect(server.providers.single['apiKey'], 'fixture-provider-key');
    expect(find.text('My provider'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await server.cleanup!();
  });

  testWidgets('tool assignment writes actual bot and tool IDs', (tester) async {
    final server = await _open(
      tester,
      ConnectedFeaturesScreen(kind: 'tools', onOpenConversation: (_) {}),
    );
    await tester.tap(find.text('Files'));
    await _frames(tester);
    await tester.tap(find.byType(SwitchListTile));
    await _frames(tester);
    expect(server.assignments.single, <String, dynamic>{
      'botId': 'scout',
      'toolId': 'file_operations',
      'enabled': true,
    });
    expect(tester.takeException(), isNull);
    await server.cleanup!();
  });
}
