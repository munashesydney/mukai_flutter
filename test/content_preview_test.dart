import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/core/response_reference.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/api/api_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/chat/widgets/file_preview.dart';
import 'package:mukai_flutter/features/chat/widgets/preview_source.dart';
import 'package:mukai_flutter/features/chat/widgets/message_bubble.dart';
import 'package:mukai_flutter/features/chat/widgets/open_content.dart';
import 'package:mukai_flutter/state/session_controller.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+afo4AAAAASUVORK5CYII=',
);

class _Api extends MukaiApiClient {
  _Api() : super('https://mukai.test', 'fixture');
  Future<void> Function()? cleanup;
  final calls = <({String path, String method, Object? body})>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    bool interactiveAccess = false,
  }) async => path.startsWith('/notifications')
      ? {'total': 0, 'unread': 0}
      : <String, dynamic>{};
  @override
  Future<DownloadedContent> downloadContent(
    String path, {
    String method = 'GET',
    Object? body,
    bool interactiveAccess = false,
    int maxBytes = 128 * 1024 * 1024,
  }) async {
    calls.add((path: path, method: method, body: body));
    if (body is Map && body['href'].toString().contains('notes.md')) {
      return DownloadedContent(
        Uint8List.fromList(
          utf8.encode(
            '# Launch notes\nOne clear next step.\nThe selected line.',
          ),
        ),
        mediaType: 'text/markdown',
        name: 'notes.md',
      );
    }
    return DownloadedContent(png, mediaType: 'image/png', name: 'preview.png');
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<_Api> _open(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _Api();
  final repo = ApiRepository(api)
    ..workspaces = [
      const MukaiWorkspace(
        id: 'w',
        name: 'Studio',
        kind: 'Folder',
        tagline: '',
      ),
    ];
  repo.workspaceId = 'w';
  final session = SessionController(repo), appearance = AppearanceController();
  var cleaned = false;
  api.cleanup = () async {
    if (cleaned) return;
    cleaned = true;
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    appearance.dispose();
  };
  addTearDown(() => api.cleanup!());
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
  await _frames(tester);
  return api;
}

void main() {
  test('response references follow desktop explicit-link rules', () {
    expect(
      parseResponseReference('mukai://artifact/file_123#L8')?.value,
      'file_123',
    );
    expect(
      parseResponseReference('mukai://file/screenshots%2Flaunch.png')?.value,
      'screenshots/launch.png',
    );
    expect(parseResponseReference('src/main.dart#L27')?.line, 27);
    expect(parseResponseReference('/workspace/a.png')?.type, 'file');
    expect(parseResponseReference(r'C:\workspace\notes.txt')?.type, 'file');
    for (final unsafe in [
      'javascript:alert(1)',
      'https://external.test/image.png',
      '//external.test',
      'mukai://attachment/%00secret',
      'file:///etc/passwd',
      'notes.md?token=secret',
    ]) {
      expect(parseResponseReference(unsafe), isNull, reason: unsafe);
    }
  });

  testWidgets(
    'view image uses the saved message context and an authenticated in-app viewer',
    (tester) async {
      final api = await _open(
        tester,
        Scaffold(
          body: ChatContentScope(
            conversationId: 'history',
            messageId: 'message-one',
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => openChatContent(
                  context,
                  'mukai-activity:tool-image',
                  name: 'Viewed image',
                  image: true,
                ),
                child: const Text('View image'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('View image'));
      await _frames(tester);
      expect(api.calls.single.path, '/conversations/history/activity-image');
      expect(api.calls.single.method, 'POST');
      expect(api.calls.single.body, {
        'messageId': 'message-one',
        'activityId': 'tool-image',
      });
      expect(find.byType(FilePreviewPage), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byTooltip('Share file'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await api.cleanup!();
    },
  );

  testWidgets('Markdown images load via the owning conversation API', (
    tester,
  ) async {
    final api = await _open(
      tester,
      Scaffold(
        body: MessageView(
          message: ChatMessage(
            id: 'm1',
            fromUser: false,
            botId: 'b1',
            conversationId: 'history',
            at: DateTime(2026),
            blocks: const [TextBlock('![Chart](mukai://file/chart.png)')],
          ),
          bots: const [],
        ),
      ),
    );
    expect(api.calls.single.path, '/conversations/history/reference');
    expect(api.calls.single.body, {
      'href': 'mukai://file/chart.png',
      'image': true,
    });
    expect(find.byType(ChatImagePreview), findsOneWidget);
    expect(tester.takeException(), isNull);
    await api.cleanup!();
  });

  testWidgets('user image attachments are visible and open a preview', (
    tester,
  ) async {
    final api = await _open(
      tester,
      Scaffold(
        body: MessageView(
          message: ChatMessage(
            id: 'upload',
            fromUser: true,
            conversationId: 'history',
            at: DateTime(2026),
            blocks: const [
              TextBlock('Have a look'),
              LinkBlock(
                title: 'Photo',
                url: 'mukai://attachment/photo',
                image: true,
              ),
            ],
          ),
          bots: const [],
        ),
      ),
    );
    expect(api.calls.single.path, '/attachments/photo');
    expect(find.byType(ChatImagePreview), findsOneWidget);
    await tester.tap(find.byType(ChatImagePreview));
    await _frames(tester);
    expect(find.byType(FilePreviewPage), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      api.calls,
      hasLength(1),
      reason: 'Opening the loaded image reuses its bytes.',
    );
    expect(tester.takeException(), isNull);
    await api.cleanup!();
  });

  testWidgets(
    'file links open text with line references instead of a share sheet',
    (tester) async {
      final api = await _open(
        tester,
        Scaffold(
          body: ChatContentScope(
            conversationId: 'history',
            messageId: 'm1',
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => openChatContent(context, 'notes.md#L3'),
                child: const Text('Launch notes'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch notes'));
      await _frames(tester);
      expect(api.calls.single.path, '/conversations/history/reference');
      expect(api.calls.single.body, {'href': 'notes.md#L3', 'image': false});
      expect(find.text('notes.md'), findsOneWidget);
      expect(find.text('The selected line.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await api.cleanup!();
    },
  );

  testWidgets(
    'PDF preview hands bytes to the native viewer without exposing a URL token',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      MethodCall? opened;
      const channel = MethodChannel('com.mukai.mobile/preview');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        opened = call;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final api = await _open(
        tester,
        FilePreviewPage(
          source: const PreviewSource(
            href: 'report.pdf',
            conversationId: 'history',
            name: 'report.pdf',
          ),
          initialContent: DownloadedContent(
            Uint8List.fromList(utf8.encode('%PDF-1.4')),
            mediaType: 'application/pdf',
            name: 'report.pdf',
          ),
        ),
      );
      expect(opened?.method, 'open');
      expect((opened?.arguments as Map)['name'], 'report.pdf');
      expect((opened?.arguments as Map)['bytes'], isA<Uint8List>());
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
      await api.cleanup!();
    },
  );
}
