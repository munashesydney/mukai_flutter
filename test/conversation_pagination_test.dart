import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';

void main() {
  test(
    'history pages retry, retain the loaded window and reject stale workspace responses',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final queries = <Map<String, String>>[];
      Completer<void>? hold;
      var failPage = false;
      final secondPageStarted = StreamController<void>.broadcast();
      Map<String, dynamic> chat(String workspace, int index) => {
        'id': '$workspace-$index',
        'workspaceId': workspace,
        'kind': 'private',
        'botIds': ['bot'],
        'ownerBotId': 'bot',
        'updatedAt': DateTime.utc(
          2026,
          11,
          9,
        ).subtract(Duration(minutes: index)).toIso8601String(),
      };
      server.listen((request) async {
        final query = request.uri.queryParameters;
        dynamic value = [];
        switch (request.uri.path) {
          case '/api/workspaces':
            value = [
              {'id': 'one', 'name': 'One'},
              {'id': 'two', 'name': 'Two'},
            ];
          case '/api/conversations':
            if (query['kind'] == 'history') {
              queries.add(Map.of(query));
              final workspace = query['workspaceId']!;
              final offset = int.parse(query['cursor'] ?? '0');
              if (offset > 0) {
                secondPageStarted.add(null);
                await hold?.future;
                if (failPage) {
                  request.response.statusCode = 503;
                  request.response.write(jsonEncode({'error': 'Try again'}));
                  await request.response.close();
                  return;
                }
              }
              value = {
                'conversations': [
                  for (var i = offset; i < offset + 12 && i < 30; i++)
                    chat(workspace, i),
                ],
                'nextCursor': offset + 12 < 30 ? '${offset + 12}' : null,
              };
            }
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(value));
        await request.response.close();
      });
      final api = MukaiApiClient('http://127.0.0.1:${server.port}', 'token');
      final repo = ApiRepository(api);
      try {
        await repo.refresh();
        expect(repo.allConversations.length, 12);
        expect(repo.hasMoreConversations, isTrue);
        failPage = true;
        await expectLater(
          repo.loadMoreConversations(),
          throwsA(isA<ApiException>()),
        );
        expect(repo.allConversations.length, 12);
        expect(repo.loadingMoreConversations, isFalse);
        failPage = false;
        await repo.loadMoreConversations();
        expect(repo.allConversations.length, 24);
        expect(queries.last['cursor'], '12');
        await repo.refresh();
        expect(repo.allConversations.length, 24);
        expect(repo.allConversations.map((chat) => chat.id).toSet().length, 24);

        hold = Completer<void>();
        final started = secondPageStarted.stream.first;
        final pending = repo.loadMoreConversations();
        await started;
        final count = queries.length;
        await repo.loadMoreConversations();
        expect(
          queries.length,
          count,
        ); // Repeated taps cannot issue duplicate requests.
        repo.workspaceId = 'two';
        await repo.refresh();
        expect(repo.allConversations.length, 12);
        hold.complete();
        await pending;
        expect(
          repo.allConversations.every((chat) => chat.id.startsWith('two-')),
          isTrue,
        );
        await repo.loadMoreConversations();
        await repo.loadMoreConversations();
        expect(repo.allConversations.length, 30);
        expect(repo.hasMoreConversations, isFalse);
      } finally {
        if (hold?.isCompleted == false) hold!.complete();
        api.close();
        await secondPageStarted.close();
        await server.close(force: true);
      }
    },
  );
}
