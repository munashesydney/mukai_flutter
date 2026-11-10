/// Run against an isolated Mukai backend with temporary data and a local test
/// provider. Never point this test at a workspace containing real user data.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mukai_flutter/app/app.dart';
import 'package:mukai_flutter/app/home_shell.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/core/connection_store.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/features/settings/timezone_screen.dart';
import 'package:mukai_flutter/features/settings/appearance_sheet.dart';
import 'package:mukai_flutter/features/auth/auth_screen.dart';
import 'package:mukai_flutter/features/chat/widgets/file_preview.dart';
import 'package:mukai_flutter/core/message_reference.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const captureUi = bool.fromEnvironment('MUKAI_CAPTURE_UI');
  const base = String.fromEnvironment('MUKAI_TEST_BASE_URL');
  const username = String.fromEnvironment('MUKAI_TEST_USERNAME');
  const password = String.fromEnvironment('MUKAI_TEST_PASSWORD');

  Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (condition()) return;
    }
    fail('The live backend UI did not reach the expected state.');
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!captureUi) return;
    // Render successive frames so theme and nested surface transitions finish.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final bytes = await binding.takeScreenshot(name);
    const captureUrl = String.fromEnvironment('MUKAI_TEST_CAPTURE_URL');
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$captureUrl/$name'));
      request.headers.contentType = ContentType('image', 'png');
      request.add(bytes);
      final response = await request.close();
      expect(response.statusCode, 204);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    // Native keyboard/route animations use the real device clock.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> destination(WidgetTester tester, String name) async {
    await waitFor(
      tester,
      () => find.byTooltip('Open sidebar').hitTestable().evaluate().isNotEmpty,
    );
    await tap(tester, find.byTooltip('Open sidebar'));
    await waitFor(
      tester,
      () => find
          .byTooltip('Search workspace')
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    if (name != 'Settings') {
      // Navigation scroll position is intentionally preserved between opens.
      await tester.drag(
        find.byKey(const PageStorageKey('sidebar-scroll')),
        const Offset(0, 600),
      );
      await tester.pump(const Duration(milliseconds: 450));
    }
    await tap(
      tester,
      name == 'Settings'
          ? find.byTooltip('Settings')
          : find.descendant(
              of: find.byKey(const PageStorageKey('sidebar-scroll')),
              matching: find.text(name),
            ),
    );
  }

  testWidgets('native app connects, streams and reads real pursuit and space data', (
    tester,
  ) async {
    expect(base, isNotEmpty, reason: 'Use the isolated backend fixture URL.');
    expect(
      username,
      isNotEmpty,
      reason: 'Use the disposable fixture owner account.',
    );
    expect(
      password,
      isNotEmpty,
      reason: 'Use the disposable fixture owner password.',
    );
    const secureStore = ConnectionStore();
    final previousConnection = await secureStore.read();
    final appearances = <AppearanceController>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final appearance in appearances) {
        appearance.dispose();
      }
      if (previousConnection == null) {
        await secureStore.clear();
      } else {
        await secureStore.save(previousConnection);
      }
    });
    await secureStore.clear();
    final appearance = AppearanceController();
    appearances.add(appearance);
    await tester.pumpWidget(
      MukaiApp(appearance: appearance, connectionStore: secureStore),
    );
    await waitFor(tester, () => find.text('Connect').evaluate().isNotEmpty);
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'The first screen asks only for the Base URL.',
    );
    await tap(tester, find.text('Using Cloudflare Zero Trust?'));
    expect(find.byType(CloudflareHelpSheet), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(CloudflareHelpSheet)).dy,
      greaterThan(40),
    );
    await tap(tester, find.byTooltip('Close Cloudflare help'));
    expect(find.byType(CloudflareHelpSheet), findsNothing);
    await tester.enterText(find.byType(TextField).first, base);
    await tap(tester, find.text('Connect'));
    await waitFor(tester, () => find.text('Sign in').evaluate().isNotEmpty);
    expect(find.text('Mukai token'), findsNothing);
    // Username/password are exchanged for an expiring device session. Neither
    // the owner password nor Mukai's master API token is persisted by the app.
    await tester.enterText(find.byType(TextField).at(0), username);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tap(tester, find.text('Sign in'));
    await waitFor(tester, () => find.byType(HomeShell).evaluate().isNotEmpty);
    final saved = await secureStore.read();
    expect(saved, isNotNull);
    expect(saved!.sessionToken, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(saved.sessionToken, isNot(password));
    final expires = saved.expiresAt;
    expect(expires.isAfter(DateTime.now()), isTrue);
    // This endpoint does not accept a master bearer token in X-Mukai-Session;
    // successful access proves that Keychain holds the scoped device session.
    final http = HttpClient();
    try {
      final request = await http.getUrl(Uri.parse('$base/api/workspaces'));
      request.headers.set('X-Mukai-Session', saved.sessionToken);
      final response = await request.close();
      expect(response.statusCode, 200);
      final workspaces =
          jsonDecode(await utf8.decoder.bind(response).join()) as List;
      expect(workspaces, isNotEmpty);
    } finally {
      http.close(force: true);
    }
    // Recreate the app against the real Keychain rather than injecting a
    // connected test session. A valid remembered session skips credential UI.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    final restoredAppearance = AppearanceController();
    appearances.add(restoredAppearance);
    await tester.pumpWidget(
      MukaiApp(appearance: restoredAppearance, connectionStore: secureStore),
    );
    await waitFor(tester, () => find.byType(HomeShell).evaluate().isNotEmpty);
    expect((await secureStore.read())!.sessionToken, saved.sessionToken);
    expect(find.text('A little momentum.'), findsNothing);
    expect(find.byTooltip('New conversation with Nova'), findsOneWidget);
    final session = MukaiScope.sessionOf(
      tester.element(find.byType(HomeShell)),
    );
    expect(session.api, isNotNull);
    expect(session.bots.length, 3);
    expect(session.recents, isNotEmpty);

    await tap(tester, find.byTooltip('Appearance'));
    await waitFor(
      tester,
      () => find.byType(AppearanceSheet).evaluate().isNotEmpty,
    );
    expect(tester.getTopLeft(find.byType(AppearanceSheet)).dy, greaterThan(40));
    await tester.dragFrom(
      tester.getTopLeft(find.byType(AppearanceSheet)) + const Offset(60, 25),
      const Offset(0, 650),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.byType(AppearanceSheet),
      findsNothing,
      reason: 'The sheet must drag down to dismiss.',
    );
    await tap(tester, find.byTooltip('Appearance'));
    await tap(tester, find.byTooltip('Close appearance'));
    expect(find.byType(AppearanceSheet), findsNothing);

    await tap(tester, find.byTooltip('Open sidebar'));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-page-canvas'))).dx,
      greaterThan(300),
    );
    await capture(tester, 'sidebar-light');
    if (captureUi) {
      restoredAppearance.setMode(ColorMode.dark);
      await tester.pump(const Duration(milliseconds: 500));
      await capture(tester, 'sidebar-dark');
    }
    await tap(tester, find.byTooltip('Search workspace'));
    await tester.enterText(
      find.byKey(const ValueKey('workspace-search-input')),
      'Nova',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await capture(tester, 'search-dark');
    await tap(tester, find.text('Nova').last);
    await waitFor(
      tester,
      () => !session.loadingThreads && session.bot.name == 'Nova',
    );
    final field = find.byType(TextField).first;
    const message = 'Hello from the native app integration test';
    await tester.enterText(field, message);
    await tap(tester, find.byTooltip('Send message'));
    await waitFor(
      tester,
      () =>
          !session.responding &&
          session.thread.any(
            (m) =>
                m.fromUser &&
                m.blocks.whereType<TextBlock>().any((b) => b.text == message),
          ) &&
          session.thread.length >= 2,
    );
    expect(session.error, isNull);
    expect(session.thread.last.fromUser, isFalse);
    expect(session.thread.last.streaming, isFalse);
    expect(session.thread.last.status, 'complete');
    expect(find.text(message), findsOneWidget);
    await tap(tester, find.byTooltip('New chat'));
    await tap(tester, find.text('Nova').last);
    await waitFor(tester, () => !session.loadingThreads);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester
          .widget<TextField>(find.byType(TextField).first)
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await session.setApprovalMode('ask-for-approval');
    await tester.enterText(
      find.byType(TextField).first,
      'Write a note for approval.',
    );
    await tap(tester, find.byTooltip('Send message'));
    try {
      await waitFor(tester, () => session.pendingApprovals.isNotEmpty);
    } catch (_) {
      await capture(tester, 'approval-timeout');
      debugPrint(
        'APPROVAL_FIXTURE_STATE: mode=${session.approvalMode} conversation=${session.conversationId} responding=${session.responding} error=${session.error} pending=${session.remote!.approvals['pending']}',
      );
      rethrow;
    }
    expect(find.byTooltip('Send message'), findsNothing);
    expect(find.text('Approval needed'), findsOneWidget);
    await capture(tester, 'approval-dark');
    await tap(tester, find.text('Approve'));
    await waitFor(
      tester,
      () => session.pendingApprovals.isEmpty && !session.responding,
    );
    expect(session.error, isNull);
    expect(find.byTooltip('Send message'), findsOneWidget);
    await session.setApprovalMode('full-access');

    await tap(tester, find.byTooltip('New chat'));
    await tap(tester, find.text('Nova').last);
    await waitFor(tester, () => !session.loadingThreads);
    await tester.enterText(find.byType(TextField).first, 'View fixture image.');
    await tap(tester, find.byTooltip('Send message'));
    await waitFor(
      tester,
      () =>
          !session.responding &&
          session.thread.any(
            (m) => m.blocks.whereType<ToolBlock>().any(
              (b) => b.previewHref != null,
            ),
          ),
    );
    await capture(tester, 'work-closed-dark');
    expect(find.text('View image'), findsNothing);
    final response = session.thread.last;
    await tap(
      tester,
      find.byKey(ValueKey('work-${response.id}-${response.startedAt}')),
    );
    await capture(tester, 'work-open-dark');
    await tap(tester, find.text('Viewed 1 image'));
    await tap(tester, find.text('View image'));
    await waitFor(
      tester,
      () => find.byType(InteractiveViewer).evaluate().isNotEmpty,
    );
    expect(find.byType(FilePreviewPage), findsOneWidget);
    await capture(tester, 'image-preview-dark');
    await tap(tester, find.byTooltip('Close preview'));
    await tap(tester, find.text('Launch notes', findRichText: true));
    await waitFor(
      tester,
      () => find
          .text('One clear outcome. Three good next steps.')
          .evaluate()
          .isNotEmpty,
    );
    await capture(tester, 'reference-preview-dark');
    await tap(tester, find.byTooltip('Close preview'));

    await destination(tester, 'Updates');
    await waitFor(
      tester,
      () =>
          find.text('Your launch has a little momentum').evaluate().isNotEmpty,
    );
    await tap(tester, find.text('Your launch has a little momentum'));
    await capture(tester, 'updates-dark');
    await tap(tester, find.text('Mark read'));
    await tap(tester, find.text('Continue in chat'));
    await waitFor(tester, () => session.reference != null);
    expect(session.reference!.label, 'Your launch has a little momentum');
    await waitFor(
      tester,
      () => find.text('Open original run').evaluate().isNotEmpty,
    );
    await tap(tester, find.text('Open original run'));
    await waitFor(
      tester,
      () => find.text('Jump in the chat').evaluate().isNotEmpty,
    );

    await destination(tester, 'Pursuits');
    await waitFor(
      tester,
      () => find.text('Bring the launch to life').evaluate().isNotEmpty,
    );
    await capture(tester, 'pursuits-dark');
    await tap(tester, find.text('Bring the launch to life'));
    await waitFor(tester, () => find.text('Workpad').evaluate().isNotEmpty);
    await capture(tester, 'pursuit-overview-dark');
    for (final title in ['Full objective', 'Success criteria']) {
      await tap(tester, find.text(title));
      await tester.pump(const Duration(milliseconds: 300));
      await tap(tester, find.text(title));
      expect(tester.takeException(), isNull);
    }
    await tap(tester, find.byTooltip('Pursuit options'));
    await tap(tester, find.text('Pause'));
    await waitFor(
      tester,
      () => find.text('Paused by request').evaluate().isNotEmpty,
    );
    await capture(tester, 'pursuit-detail-dark');
    final runRow = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('pursuit-run-'),
    );
    await tap(tester, runRow);
    await waitFor(
      tester,
      () => find.text('Jump in the chat').evaluate().isNotEmpty,
    );
    await capture(tester, 'run-conversation-dark');
    await tap(tester, find.text('Run outcome'));
    await capture(tester, 'run-summary-dark');
    await tap(tester, find.text('Chat'));
    await tap(tester, find.text('Jump in the chat'));
    await tester.enterText(
      find.byType(TextField).first,
      'What is the next step for this run?',
    );
    await tap(tester, find.byTooltip('Send message'));
    await waitFor(
      tester,
      () =>
          !session.responding &&
          session.thread.any(
            (message) =>
                message.fromUser &&
                message.blocks.whereType<TextBlock>().any(
                  (block) =>
                      block.text == 'What is the next step for this run?',
                ),
          ),
    );

    session.setReference(
      const MessageReference(
        label: 'Launch review',
        text: 'Keep the next step small and useful.',
      ),
    );
    await tester.enterText(
      find.byType(TextField).first,
      'Give me a slow explanation of the launch plan.',
    );
    await tap(tester, find.byTooltip('Send message'));
    await waitFor(
      tester,
      () => session.responding && session.activeReply != null,
    );
    await tap(tester, find.byType(TextField).first);
    await tester.enterText(
      find.byType(TextField).first,
      'Focus on the next practical step.',
    );
    await tester.pump();
    final composerInput = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(composerInput.controller!.text, 'Focus on the next practical step.');
    await waitFor(
      tester,
      () => find.byTooltip('Queue follow-up').evaluate().isNotEmpty,
    );
    await tap(tester, find.byTooltip('Queue follow-up'));
    await waitFor(tester, () => session.followups.isNotEmpty);
    await tap(tester, find.text('Steer'));
    await waitFor(
      tester,
      () => !session.responding && session.followups.isEmpty,
    );
    expect(session.error, isNull);
    expect(
      session.thread
          .expand((message) => message.blocks)
          .whereType<SteeringBlock>()
          .single
          .text,
      'Focus on the next practical step.',
    );
    expect(find.text('You steered this task'), findsOneWidget);

    await destination(tester, 'Spaces');
    await waitFor(
      tester,
      () => find.text('The launch room').evaluate().isNotEmpty,
    );
    await tap(tester, find.text('The launch room'));
    await waitFor(tester, () => session.isSpace && !session.loadingThreads);
    expect(session.error, isNull);
    expect(session.conversationId, isNotNull);
    expect(find.text('The launch room'), findsWidgets);
    await tester.enterText(
      find.byType(TextField).first,
      'A hello from our shared space',
    );
    await tap(tester, find.byTooltip('Send message'));
    await waitFor(
      tester,
      () => !session.responding && session.thread.isNotEmpty,
    );
    expect(session.error, isNull);
    expect(session.thread.last.status, 'complete');
    await destination(tester, 'Settings');
    await waitFor(tester, () => find.text('Timezone').evaluate().isNotEmpty);
    expect(session.workspace.timeZone, 'America/Vancouver');
    await tap(tester, find.text('Timezone'));
    await waitFor(
      tester,
      () => find.byType(TimezoneScreen).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Search timezones'),
      'Kathmandu',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, find.text('Asia/Kathmandu'));
    expect(find.textContaining('UTC+05:45'), findsOneWidget);
    // Dismiss the native keyboard before capturing and saving the shared value.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    await capture(tester, 'timezone-dark');
    await tap(tester, find.text('Save timezone'));
    await waitFor(tester, () => find.byType(TimezoneScreen).evaluate().isEmpty);
    expect(session.workspace.timeZone, 'Asia/Kathmandu');
    await session.loadRecents();
    expect(session.workspace.timeZone, 'Asia/Kathmandu');
    final clockEvents =
        await session.api!.events('/bots/${session.bots.first.id}/chat', {
          'requestId': newRequestId(),
          'text': 'Check workspace clock',
          'attachmentIds': <String>[],
        }).toList();
    expect(
      clockEvents.toString(),
      contains('Workspace timezone: Asia/Kathmandu'),
    );
    expect(clockEvents.toString(), contains('+05:45'));
    await waitFor(
      tester,
      () => find.text('Disconnect this iPhone').evaluate().isNotEmpty,
    );
    await tap(tester, find.text('Disconnect this iPhone'));
    await tap(tester, find.widgetWithText(TextButton, 'Disconnect'));
    await waitFor(tester, () => find.text('Connect').evaluate().isNotEmpty);
    expect(await secureStore.read(), isNull);
    final signedOutHttp = HttpClient();
    try {
      final request = await signedOutHttp.getUrl(
        Uri.parse('$base/api/workspaces'),
      );
      request.headers.set('X-Mukai-Session', saved.sessionToken);
      final response = await request.close();
      expect(
        response.statusCode,
        401,
        reason: 'Disconnect revokes the device session on the server.',
      );
      await response.drain<void>();
    } finally {
      signedOutHttp.close(force: true);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
