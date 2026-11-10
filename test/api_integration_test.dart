import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/state/session_controller.dart';
import 'package:mukai_flutter/core/message_reference.dart';

Map<String, dynamic> _message(
  String id,
  String text, {
  String role = 'assistant',
  String status = 'complete',
  String conversationId = 'history-chat',
}) => <String, dynamic>{
  'id': id,
  'requestId': 'server-request',
  'botId': 'bot-one',
  'role': role,
  'content': text,
  'status': status,
  'error': null,
  'createdAt': '2026-11-03T10:00:00Z',
  'attachments': <dynamic>[],
  'conversationId': conversationId,
};

class _Recorded {
  _Recorded(this.method, this.uri, this.body, this.authorization);
  final String method;
  final Uri uri;
  final dynamic body;
  final String? authorization;
}

/// A real local HTTP boundary with only Mukai's documented JSON/SSE contracts.
class _MukaiServer {
  late HttpServer server;
  final List<_Recorded> requests = [];
  final Map<String, List<Map<String, dynamic>>> history = {
    'history-chat': [_message('saved-assistant', 'Saved history')],
    'other-chat': [_message('other-assistant', 'Other conversation')],
    'server-created-chat': [],
    'bot-bot-one': [_message('primary-assistant', 'Primary bot history')],
  };
  Map<String, dynamic> approvals = {
    'mode': 'ask-for-approval',
    'pending': <dynamic>[],
  };
  final Map<String, List<Map<String, dynamic>>> followupQueues = {};
  bool twoWorkspaces = false;
  String? workspaceOneTimeZone;
  Completer<void>? workspaceReadGate;
  Completer<void>? workspaceOneBotsGate;
  Completer<void>? followupPostGate;
  final List<String> handlerFailures = [];
  bool holdReply = false;
  bool interruptReply = false;
  bool failReply = false;
  bool dropChatBeforeFirstEvent = false;
  bool persistDroppedRequest = false;
  Completer<void>? _finishReply;
  bool _stopped = false;

  String get url => 'http://127.0.0.1:${server.port}';
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await _handle(request);
      } catch (error) {
        if (error is! HttpException && error is! SocketException) {
          handlerFailures.add(error.toString());
        }
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> close() async {
    if (workspaceReadGate?.isCompleted == false) workspaceReadGate!.complete();
    if (workspaceOneBotsGate?.isCompleted == false) {
      workspaceOneBotsGate!.complete();
    }
    if (followupPostGate?.isCompleted == false) followupPostGate!.complete();
    if (_finishReply != null && !_finishReply!.isCompleted) {
      _finishReply!.complete();
    }
    await server.close(force: true);
  }

  Future<void> _json(
    HttpRequest request,
    dynamic value, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(value));
    await request.response.close();
  }

  Future<void> _event(
    HttpResponse response,
    Map<String, dynamic> event, {
    bool split = false,
  }) async {
    final bytes = utf8.encode('data: ${jsonEncode(event)}\n\n');
    if (split) {
      // Deliberately split both a JSON line and the UTF-8 bytes for an emoji.
      for (int offset = 0; offset < bytes.length; offset += 3) {
        response.add(
          bytes.sublist(offset, (offset + 3).clamp(0, bytes.length)),
        );
        await response.flush();
      }
    } else {
      response.add(bytes);
      await response.flush();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    dynamic body;
    final raw = await utf8.decoder.bind(request).join();
    if (raw.isNotEmpty) body = jsonDecode(raw);
    requests.add(
      _Recorded(
        request.method,
        request.uri,
        body,
        request.headers.value(HttpHeaders.authorizationHeader),
      ),
    );
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer owner-test-token') {
      return _json(request, {'error': 'Unauthorized'}, status: 401);
    }
    final path = request.uri.path.replaceFirst('/api', '');
    if (path == '/redirect') {
      request.response.statusCode = 302;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        '$url/api/workspaces',
      );
      await request.response.close();
      return;
    }
    if (path == '/html') {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>wrong target</html>');
      await request.response.close();
      return;
    }
    if (path == '/workspaces') {
      final snapshot = [
        {
          'id': 'workspace-one',
          'name': 'Live workspace',
          'folder': '/project',
          'computer': 'local',
          'createdAt': '2026-11-03T00:00:00Z',
          if (workspaceOneTimeZone != null) 'timeZone': workspaceOneTimeZone,
        },
        if (twoWorkspaces)
          {
            'id': 'workspace-two',
            'name': 'Other workspace',
            'folder': '/other',
            'computer': 'local',
            'createdAt': '2026-11-03T00:00:00Z',
            'timeZone': 'UTC',
          },
      ];
      if (workspaceReadGate != null) await workspaceReadGate!.future;
      return _json(request, snapshot);
    }
    if (path == '/workspaces/workspace-one/timezone' &&
        request.method == 'PUT') {
      workspaceOneTimeZone = body['timeZone'] as String;
      return _json(request, {
        'id': 'workspace-one',
        'name': 'Live workspace',
        'computer': 'local',
        'timeZone': workspaceOneTimeZone,
      });
    }
    if (path == '/bots') {
      final requestedWorkspace = request.uri.queryParameters['workspaceId'];
      if (requestedWorkspace == 'workspace-one' &&
          workspaceOneBotsGate != null) {
        await workspaceOneBotsGate!.future;
      }
      if (requestedWorkspace == 'workspace-two') {
        return _json(request, [
          {
            'id': 'bot-two',
            'workspaceId': 'workspace-two',
            'name': 'Other Scout',
            'role': 'Builder',
            'avatar': 'mukai-logo',
            'isMain': true,
            'model': null,
          },
        ]);
      }
      return _json(request, [
        {
          'id': 'bot-one',
          'workspaceId': 'workspace-one',
          'name': 'Real Scout',
          'role': 'Main Bot/Orchestrator',
          'avatar': 'muka-mascot-2-blue',
          'isMain': true,
          'model': null,
        },
      ]);
    }
    if (path == '/conversations') {
      final conversations = <Map<String, dynamic>>[
        {
          'id': 'history-chat',
          'workspaceId': 'workspace-one',
          'kind': 'private',
          'name': 'Server history',
          'isWorking': history['history-chat']!.any(
            (m) => m['status'] == 'streaming',
          ),
          'description': 'Selected thread',
          'botIds': ['bot-one'],
          'ownerBotId': 'bot-one',
          'updatedAt': '2026-11-03T00:00:00Z',
        },
        {
          'id': 'other-chat',
          'workspaceId': 'workspace-one',
          'kind': 'space',
          'name': 'Team space',
          'description': 'Shared',
          'botIds': ['bot-one'],
          'ownerBotId': null,
          'updatedAt': '2026-11-02T00:00:00Z',
        },
      ];
      final kind = request.uri.queryParameters['kind'] ?? 'space';
      return _json(
        request,
        conversations.where((c) => c['kind'] == kind).toList(),
      );
    }
    if (path == '/providers') return _json(request, <dynamic>[]);
    if (path == '/approvals') {
      if (request.method == 'PUT') approvals['mode'] = body['mode'];
      return _json(request, approvals);
    }
    if (path == '/approvals/approval-one') {
      approvals['pending'] = <dynamic>[];
      return _json(request, approvals);
    }
    if (path == '/bots/bot-one/conversations') {
      return _json(request, {'id': 'server-created-chat'});
    }
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length == 3 &&
        (parts.first == 'conversations' || parts.first == 'bots')) {
      final key = parts.first == 'bots' ? 'bot-${parts[1]}' : parts[1];
      final action = parts[2];
      if (action == 'messages') {
        return _json(request, history[key] ?? <dynamic>[]);
      }
      if (action == 'artifacts' || action == 'attachments') {
        return _json(request, <dynamic>[]);
      }
      if (action == 'followups') {
        final followups = followupQueues.putIfAbsent(key, () => []);
        if (request.method == 'POST') {
          followups.add({
            'id': body['id'],
            'conversationId': key,
            'botId': 'bot-one',
            'text': body['text'],
            'state': 'queued',
            'createdAt': '2026-11-03T10:00:00Z',
          });
        } else if (request.method == 'PUT') {
          if (body['action'] == 'delete') {
            followups.removeWhere((item) => item['id'] == body['id']);
          }
          if (body['action'] == 'edit') {
            for (final item in followups) {
              if (item['id'] == body['id']) item['text'] = body['text'];
            }
          }
          if (body['action'] == 'steer') {
            for (final item in followups) {
              if (item['id'] == body['id']) item['state'] = 'steering';
            }
          }
        }
        if (request.method == 'POST' && followupPostGate != null) {
          await followupPostGate!.future;
        }
        return _json(request, followups);
      }
      if (action == 'stop') {
        _stopped = true;
        if (_finishReply != null && !_finishReply!.isCompleted) {
          _finishReply!.complete();
        }
        return _json(request, {'ok': true});
      }
      if (action == 'retry' && parts.first == 'conversations') {
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        final assistantId = body['messageId'] as String;
        final user = history[key]!.firstWhere((m) => m['role'] == 'user');
        final pending = _message(
          assistantId,
          '',
          status: 'streaming',
          conversationId: key,
        );
        await _event(request.response, {
          'type': 'start',
          'user': user,
          'assistant': pending,
        });
        final done = _message(
          assistantId,
          'Retry completed',
          conversationId: key,
        );
        history[key] = [user, done];
        await _event(request.response, {'type': 'done', 'message': done});
        await request.response.close();
        return;
      }
      if (action == 'chat') {
        if (dropChatBeforeFirstEvent) {
          dropChatBeforeFirstEvent = false;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          if (persistDroppedRequest) {
            final user = _message(
              'server-user',
              body['text'] as String,
              role: 'user',
              conversationId: key,
            );
            final assistant = _message(
              'server-assistant',
              'Saved despite lost receipt',
              status: 'interrupted',
              conversationId: key,
            );
            user['requestId'] = body['requestId'];
            assistant['requestId'] = body['requestId'];
            history[key] = [...?history[key], user, assistant];
          }
          await request.response.close();
          return;
        }
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        final user = _message(
          'server-user',
          body['text'] as String,
          role: 'user',
          conversationId: key,
        );
        final assistant = _message(
          'server-assistant',
          '',
          status: 'streaming',
          conversationId: key,
        );
        user['requestId'] = body['requestId'] ?? 'server-request';
        assistant['requestId'] = body['requestId'] ?? 'server-request';
        history[key] = [...?history[key], user, assistant];
        await _event(request.response, {
          'type': 'start',
          'user': user,
          'assistant': assistant,
        });
        await _event(request.response, {
          'type': 'delta',
          'id': 'server-assistant',
          'partId': 'part-one',
          'text': 'Hello 🌱',
        }, split: true);
        if (interruptReply) {
          assistant['status'] = 'interrupted';
          assistant['content'] = 'Hello 🌱';
          await request.response.close();
          return;
        }
        if (holdReply) {
          _finishReply = Completer<void>();
          await _finishReply!.future;
        }
        final done = _message(
          'server-assistant',
          'Hello 🌱',
          status: failReply
              ? 'failed'
              : _stopped
              ? 'stopped'
              : 'complete',
          conversationId: key,
        );
        done['requestId'] = body['requestId'] ?? 'server-request';
        if (failReply) done['error'] = 'Provider rejected this request.';
        history[key] = [
          ...history[key]!.where((m) => m['id'] != 'server-assistant'),
          done,
        ];
        await _event(request.response, {
          'type': failReply ? 'error' : 'done',
          'message': done,
        });
        await request.response.close();
        return;
      }
      if (action == 'saved') {
        for (final message in history[key] ?? <Map<String, dynamic>>[]) {
          if (message['id'] == body['messageId']) {
            message['saved'] = body['saved'];
          }
        }
        return _json(
          request,
          history[key]!.firstWhere((m) => m['id'] == body['messageId']),
        );
      }
    }
    return _json(request, {
      'error': 'Unexpected fixture endpoint $path',
    }, status: 404);
  }
}

Future<void> _until(bool Function() condition) async {
  for (int attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for the HTTP-driven state change.');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  late _MukaiServer server;
  late MukaiApiClient client;
  setUp(() async {
    server = _MukaiServer();
    await server.start();
    client = MukaiApiClient(server.url, 'owner-test-token');
  });
  tearDown(() async {
    client.close();
    await server.close();
    expect(server.handlerFailures, isEmpty);
  });

  test(
    'workspace zones refresh during a chat while timestamps and drafts remain intact',
    () async {
      server.workspaceOneTimeZone = 'America/Vancouver';
      server.twoWorkspaces = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      session.drafts[session.draftKey] = 'An unsent draft';
      final instant = session.thread.single.at;
      expect(instant.isUtc, isTrue);
      expect(session.workspace.timeZone, 'America/Vancouver');
      server.workspaceOneTimeZone = 'Asia/Kathmandu';
      await session.refreshLive();
      expect(session.workspace.timeZone, 'Asia/Kathmandu');
      expect(session.thread.single.at, instant);
      expect(session.drafts[session.draftKey], 'An unsent draft');
      await session.selectWorkspace('workspace-two');
      expect(session.workspace.timeZone, 'UTC');
      await session.setWorkspaceTimeZone('workspace-one', 'Europe/London');
      expect(session.workspace.id, 'workspace-two');
      expect(session.workspace.timeZone, 'UTC');
      expect(
        session.workspaces.firstWhere((w) => w.id == 'workspace-one').timeZone,
        'Europe/London',
      );
      expect(server.requests.last.body, {'timeZone': 'Europe/London'});
    },
  );

  test('a delayed settings read cannot overwrite a saved timezone', () async {
    server.workspaceOneTimeZone = 'America/Vancouver';
    final repo = ApiRepository(client);
    await repo.refresh();
    final reads = server.requests
        .where((r) => r.uri.path == '/api/workspaces')
        .length;
    server.workspaceReadGate = Completer<void>();
    final pending = repo.refreshWorkspaceSettings();
    await _until(
      () =>
          server.requests.where((r) => r.uri.path == '/api/workspaces').length >
          reads,
    );
    await repo.saveWorkspaceTimeZone('workspace-one', 'Asia/Kathmandu');
    server.workspaceReadGate!.complete();
    await pending;
    expect(repo.workspace.timeZone, 'Asia/Kathmandu');
    final before = server.requests.length;
    await expectLater(
      repo.saveWorkspaceTimeZone('workspace-one', 'PST'),
      throwsA(isA<ApiException>()),
    );
    expect(server.requests.length, before);
  });

  test(
    'normalizes host, API prefix and reverse-proxy paths without duplicating api',
    () {
      expect(
        MukaiApiClient.normalizeBase('https://mukai.example/').toString(),
        'https://mukai.example/api',
      );
      expect(
        MukaiApiClient.normalizeBase('https://mukai.example/api/').toString(),
        'https://mukai.example/api',
      );
      expect(
        MukaiApiClient.normalizeBase('https://mukai.example/team').toString(),
        'https://mukai.example/team/api',
      );
      expect(
        () => MukaiApiClient.normalizeBase('https://user:secret@mukai.example'),
        throwsA(isA<ApiException>()),
      );
      expect(() => client.uri('https://foreign.example'), throwsArgumentError);
    },
  );

  test(
    'sends owner bearer and JSON, rejects token and never follows redirects',
    () async {
      final workspaces = await client.request('/workspaces');
      expect((workspaces as List).first['id'], 'workspace-one');
      expect(server.requests.single.authorization, 'Bearer owner-test-token');
      await client.request(
        '/approvals?workspaceId=workspace-one',
        method: 'PUT',
        body: {'mode': 'full-access'},
      );
      expect(server.requests.last.body, {'mode': 'full-access'});
      expect(
        server.requests.last.uri.queryParameters['workspaceId'],
        'workspace-one',
      );
      final before = server.requests.length;
      await expectLater(
        client.request('/redirect'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 302)),
      );
      expect(server.requests.length, before + 1);
      final wrong = MukaiApiClient(server.url, 'wrong');
      addTearDown(wrong.close);
      await expectLater(
        wrong.request('/workspaces'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      await expectLater(
        client.request('/html'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Base URL'),
          ),
        ),
      );
    },
  );

  test('decodes fragmented UTF-8 SSE and requires a terminal event', () async {
    final events = await client.events('/conversations/history-chat/chat', {
      'text': 'hi',
      'requestId': newRequestId(),
      'attachmentIds': <String>[],
    }).toList();
    expect(events.map((e) => e['type']), ['start', 'delta', 'done']);
    expect(events[1]['text'], 'Hello 🌱');
    server.interruptReply = true;
    await expectLater(
      client.events('/conversations/other-chat/chat', {'text': 'hi'}).toList(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('interrupted'),
        ),
      ),
    );
  });

  test(
    'repository maps live identities and loads the exact selected conversation',
    () async {
      final repo = ApiRepository(client);
      await repo.refresh();
      expect(repo.workspace.id, 'workspace-one');
      expect(repo.bots.single.name, 'Real Scout');
      expect(repo.bots.single.mascot, 'muka-mascot-2-blue');
      final thread = await repo.loadThread(
        'bot-one',
        conversationId: 'other-chat',
      );
      expect(thread.single.id, 'other-assistant');
      expect(
        thread.single.blocks.whereType<TextBlock>().single.text,
        'Other conversation',
      );
      expect(repo.allConversations.last.kind, 'space');
      expect(repo.recentConversations().single.id, 'history-chat');
      expect(
        server.requests
            .where((r) => r.uri.path == '/api/conversations')
            .map((r) => r.uri.queryParameters['kind']),
        containsAll([null, 'private', 'bot']),
      );
      expect(
        server.requests.any(
          (r) => r.uri.path == '/api/conversations/other-chat/messages',
        ),
        isTrue,
      );
    },
  );

  test(
    'new conversation uses server-created ID and sends a real stream without duplicate turns',
    () async {
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', fresh: true);
      expect(session.error, isNull);
      expect(session.conversationId, 'server-created-chat');
      expect(session.thread, isEmpty);
      await session.send('Make a plan');
      await _until(() => !session.responding);
      expect(session.thread.where((m) => m.fromUser).map((m) => m.id), [
        'server-user',
      ]);
      expect(session.thread.where((m) => !m.fromUser).map((m) => m.id), [
        'server-assistant',
      ]);
      expect(
        session.thread.last.blocks.whereType<TextBlock>().single.text,
        'Hello 🌱',
      );
      final send = server.requests.firstWhere(
        (r) => r.uri.path.endsWith('/chat'),
      );
      expect(send.uri.path, '/api/conversations/server-created-chat/chat');
      expect(
        send.body['requestId'],
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );

  test(
    'follow-ups queue during a response and stop targets the selected conversation',
    () async {
      server.holdReply = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      final send = session.send('Start working');
      try {
        await _until(
          () => session.thread.any((m) => m.id == 'server-assistant'),
        );
      } catch (_) {
        fail(
          'No streaming assistant: error=${session.error}; ids=${session.thread.map((m) => m.id).toList()}; requests=${server.requests.map((r) => r.uri.path).toList()}',
        );
      }
      expect(session.responding, isTrue);
      const reference = MessageReference(
        label: 'Review',
        text: 'Quoted notes\n\nKeep their context.',
      );
      session.setReference(reference);
      await session.send('Also check the notes');
      expect(
        session.followups.single['text'],
        reference.format('Also check the notes'),
      );
      expect(session.reference, isNull);
      final queue = server.requests.firstWhere(
        (r) => r.method == 'POST' && r.uri.path.endsWith('/followups'),
      );
      expect(queue.uri.path, '/api/conversations/history-chat/followups');
      await session.updateFollowup(
        session.followups.single['id'] as String,
        'edit',
        text: reference.format('Updated notes'),
      );
      expect(
        session.followups.single['text'],
        reference.format('Updated notes'),
      );
      final activeRequest = session.activeReply!.requestId;
      expect(
        await session.updateFollowup(
          session.followups.single['id'] as String,
          'steer',
        ),
        isTrue,
      );
      expect(session.followups.single['state'], 'steering');
      final steer = server.requests.lastWhere(
        (r) => r.body is Map && r.body['action'] == 'steer',
      );
      expect(steer.body['expectedRequestId'], activeRequest);
      await session.updateFollowup(
        session.followups.single['id'] as String,
        'delete',
      );
      expect(session.followups, isEmpty);
      session.stop();
      await send;
      await _until(() => !session.responding);
      expect(
        server.requests.any(
          (r) =>
              r.uri.path == '/api/conversations/history-chat/stop' &&
              r.method == 'POST',
        ),
        isTrue,
      );
      expect(session.thread.last.status, 'stopped');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );

  test(
    'selecting a bot after a private chat returns to its primary conversation',
    () async {
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      expect(session.conversationId, 'history-chat');
      await session.openBot('bot-one');
      expect(session.conversationId, isNull);
      expect(session.thread.single.id, 'primary-assistant');
      expect(
        server.requests.any((r) => r.uri.path == '/api/bots/bot-one/messages'),
        isTrue,
      );
    },
  );

  test(
    'switching conversations completes the local send future without stopping the server run',
    () async {
      server.holdReply = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      final send = session.send('Work while I read another chat');
      expect(session.workingConversationIds, contains('history-chat'));
      expect(session.workingBotIds, contains('bot-one'));
      await _until(() => session.thread.any((m) => m.id == 'server-assistant'));
      await session
          .openBot('bot-one', conversationId: 'other-chat')
          .timeout(const Duration(seconds: 3));
      await send.timeout(const Duration(seconds: 3));
      expect(session.conversationId, 'other-chat');
      expect(session.thread.single.id, 'other-assistant');
      expect(session.workingConversationIds, contains('history-chat'));
      await session.loadRecents();
      expect(repo.recentConversations().single.isWorking, isTrue);
      expect(session.workingConversationIds, contains('history-chat'));
      server._finishReply!.complete();
      await _until(
        () => !server.history['history-chat']!.any(
          (m) => m['status'] == 'streaming',
        ),
      );
      await session.loadRecents();
      expect(session.workingConversationIds, isNot(contains('history-chat')));
      expect(session.workingBotIds, isNot(contains('bot-one')));
      expect(
        server.requests.where((r) => r.uri.path.endsWith('/stop')),
        isEmpty,
      );
    },
  );

  test(
    'a server error event retains the failed response and its actual error',
    () async {
      server.failReply = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      await session.send('Ask a failing provider');
      expect(session.responding, isFalse);
      expect(session.thread.last.status, 'failed');
      expect(session.thread.last.error, 'Provider rejected this request.');
      expect(session.thread.where((m) => m.id == 'server-user').length, 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );

  test(
    'delegated tool approvals remain visible in the blocked parent conversation',
    () async {
      server.approvals['pending'] = [
        {
          'id': 'delegated-approval',
          'messageId': 'child-assistant',
          'conversationId': 'child-chat',
          'botId': 'child-bot',
          'toolName': 'write_file',
          'input': {'path': 'notes.md'},
          'blockedParents': [
            {
              'messageId': 'saved-assistant',
              'conversationId': 'history-chat',
              'botId': 'bot-one',
              'botName': 'Real Scout',
            },
          ],
        },
      ];
      final repo = ApiRepository(client);
      await repo.refresh();
      final thread = await repo.loadThread(
        'bot-one',
        conversationId: 'history-chat',
      );
      expect(
        thread.single.blocks.whereType<ApprovalBlock>().single.id,
        'delegated-approval',
      );
    },
  );

  test(
    'primary bot retry uses conversation retry and does not create a second user turn',
    () async {
      server.history['bot-bot-one'] = [
        _message(
          'original-user',
          'Original question',
          role: 'user',
          conversationId: 'bot-bot-one',
        ),
        _message(
          'primary-assistant',
          'Partial reply',
          status: 'failed',
          conversationId: 'bot-bot-one',
        ),
      ];
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one');
      await session.retryMessage(session.thread.last);
      expect(
        server.requests.any(
          (r) => r.uri.path == '/api/conversations/bot-bot-one/retry',
        ),
        isTrue,
      );
      expect(session.thread.where((m) => m.fromUser).map((m) => m.id), [
        'original-user',
      ]);
      expect(session.thread.last.id, 'primary-assistant');
      expect(session.thread.last.status, 'complete');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );

  test(
    'an accepted interrupted request is not restored as a duplicate send draft',
    () async {
      server.interruptReply = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      await session.send('Accepted on the server');
      expect(session.thread.any((m) => m.id == 'server-user'), isTrue);
      expect(session.drafts[session.draftKey] ?? '', isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );

  test('stream completion preserves a newer follow-up draft', () async {
    server.holdReply = true;
    final repo = ApiRepository(client);
    await repo.refresh();
    final session = SessionController(repo);
    addTearDown(session.dispose);
    await session.openBot('bot-one', conversationId: 'history-chat');
    final send = session.send('First request');
    await _until(() => session.thread.any((m) => m.id == 'server-assistant'));
    session.drafts[session.draftKey] = 'My next thought';
    session.stop();
    await send;
    expect(session.drafts[session.draftKey], 'My next thought');
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test(
    'a delayed workspace refresh cannot replace the newly selected workspace data',
    () async {
      server.twoWorkspaces = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      server.workspaceOneBotsGate = Completer<void>();
      final stale = repo.refresh();
      await _until(
        () =>
            server.requests
                .where(
                  (r) =>
                      r.uri.path == '/api/bots' &&
                      r.uri.queryParameters['workspaceId'] == 'workspace-one',
                )
                .length ==
            2,
      );
      repo.workspaceId = 'workspace-two';
      await repo.refresh();
      expect(repo.bots.single.id, 'bot-two');
      server.workspaceOneBotsGate!.complete();
      await stale;
      expect(repo.workspace.id, 'workspace-two');
      expect(repo.bots.single.id, 'bot-two');
    },
  );

  test(
    'a delayed queued follow-up does not clear the next conversation draft or files',
    () async {
      server.holdReply = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      final send = session.send('Working request');
      await _until(() => session.thread.any((m) => m.id == 'server-assistant'));
      server.followupPostGate = Completer<void>();
      final queued = session.send('Old chat follow-up');
      await _until(
        () => server.requests.any(
          (r) => r.method == 'POST' && r.uri.path.endsWith('/followups'),
        ),
      );
      await session.openBot('bot-one', conversationId: 'other-chat');
      await send;
      session.drafts[session.draftKey] = 'New chat draft';
      session.attachments.add({'id': 'new-chat-file', 'name': 'new.txt'});
      server.followupPostGate!.complete();
      await queued;
      expect(session.drafts[session.draftKey], 'New chat draft');
      expect(session.attachments.single['id'], 'new-chat-file');
      expect(session.followups, isEmpty);
    },
  );

  test(
    'a lost first stream event reconciles server acceptance before restoring a duplicate draft',
    () async {
      server.dropChatBeforeFirstEvent = true;
      server.persistDroppedRequest = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      await session.send('Accepted before the receipt was lost');
      await _until(
        () =>
            session.thread.any((m) => m.id == 'server-user') &&
            (session.drafts[session.draftKey] ?? '').isEmpty,
      );
      expect(session.thread.where((m) => m.id == 'server-user').length, 1);
      expect(
        server.requests.where((r) => r.uri.path.endsWith('/chat')).length,
        1,
      );
    },
  );

  test(
    'retrying an uncertain unaccepted send reuses its original request UUID',
    () async {
      server.dropChatBeforeFirstEvent = true;
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      await session.send('Keep this exact request identity');
      expect(
        session.drafts[session.draftKey],
        'Keep this exact request identity',
      );
      await session.send('Keep this exact request identity');
      final sends = server.requests
          .where((r) => r.uri.path.endsWith('/chat'))
          .toList();
      expect(sends.length, 2);
      expect(sends[1].body['requestId'], sends[0].body['requestId']);
      expect(session.thread.where((m) => m.id == 'server-user').length, 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );

  test(
    'a rejected token invokes the unauthorized callback exactly once per response',
    () async {
      final invalid = MukaiApiClient(server.url, 'invalid-token');
      addTearDown(invalid.close);
      int callbacks = 0;
      invalid.onUnauthorized = () => callbacks++;
      await expectLater(
        invalid.request('/workspaces'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(callbacks, 1);
    },
  );

  test(
    'denial reasons are sent with the exact pending approval and workspace',
    () async {
      server.approvals['pending'] = [
        {
          'id': 'approval-one',
          'messageId': 'saved-assistant',
          'conversationId': 'history-chat',
          'botId': 'bot-one',
          'toolName': 'communicate',
          'input': {},
          'ask': {'action': 'approval', 'question': 'Publish?'},
        },
      ];
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      await session.resolveApproval(
        session.pendingApprovals.single,
        approved: false,
        reason: '  Revise the audience first.  ',
      );
      final decision = server.requests.firstWhere(
        (r) => r.uri.path == '/api/approvals/approval-one',
      );
      expect(decision.body, {
        'approved': false,
        'reason': 'Revise the audience first.',
      });
      expect(decision.uri.queryParameters['workspaceId'], 'workspace-one');
    },
  );

  test(
    'approval IDs, workspace scope and saved messages use server mutations',
    () async {
      server.approvals['pending'] = [
        {
          'id': 'approval-one',
          'messageId': 'saved-assistant',
          'conversationId': 'history-chat',
          'botId': 'bot-one',
          'toolName': 'write_file',
          'input': {'path': 'notes.md'},
          'ask': null,
        },
      ];
      final repo = ApiRepository(client);
      await repo.refresh();
      final session = SessionController(repo);
      addTearDown(session.dispose);
      await session.openBot('bot-one', conversationId: 'history-chat');
      final approval = session.thread.single.blocks
          .whereType<ApprovalBlock>()
          .single;
      expect(approval.id, 'approval-one');
      session.resolveApproval(approval, approved: true);
      await _until(
        () => server.requests.any(
          (r) => r.uri.path == '/api/approvals/approval-one',
        ),
      );
      final decision = server.requests.firstWhere(
        (r) => r.uri.path == '/api/approvals/approval-one',
      );
      expect(decision.uri.queryParameters['workspaceId'], 'workspace-one');
      expect(decision.body, {'approved': true});
      await _until(
        () => !session.thread.single.blocks.any((b) => b is ApprovalBlock),
      );
      await session.saveMessage(session.thread.single);
      expect(
        server.requests
            .lastWhere(
              (r) => r.method == 'PUT' && r.uri.path.endsWith('/saved'),
            )
            .body,
        {'messageId': 'saved-assistant', 'saved': true},
      );
      await _until(() => session.thread.single.saved);
    },
  );
}
