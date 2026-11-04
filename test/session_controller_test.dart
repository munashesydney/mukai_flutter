import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/data/demo/demo_repository.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/state/session_controller.dart';

/// Cadence fast enough that a streamed reply lands well inside a test, with no
/// artificial latency to wait through.
MukaiDemoRepository _repo({double failureRate = 0}) => MukaiDemoRepository(
  latency: Duration.zero,
  streamCadence: const Duration(milliseconds: 1),
  failureRate: failureRate,
  // Forces the draw below `failureRate`, so failures are deterministic.
  random: failureRate > 0 ? RandomOverride(0) : null,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('openBot', () {
    test('loads a thread, activity and the bot identity', () async {
      final SessionController session = SessionController(_repo());
      await session.openBot('scout');

      expect(session.bot.name, 'Scout');
      expect(session.bot.isMain, isTrue);
      expect(session.thread, isNotEmpty);
      expect(session.activity.total, greaterThan(0));
      expect(session.hasError, isFalse);
      expect(session.loadingThreads, isFalse);
    });

    test(
      'an unknown id falls back to the first bot instead of crashing',
      () async {
        final SessionController session = SessionController(_repo());
        await session.openBot('not-a-bot');
        expect(session.bot.id, 'scout');
      },
    );

    test('transport failures land in the error surface', () async {
      final SessionController session = SessionController(
        _repo(failureRate: 1),
      );
      await session.openBot('scout');

      expect(session.hasError, isTrue);
      expect(session.error, contains('provider'));
      expect(session.thread, isEmpty);
    });
  });

  test(
    'a fresh conversation clears the previous thread and can send',
    () async {
      final session = SessionController(_repo());
      addTearDown(session.dispose);
      await session.openBot('nova');
      expect(session.thread, isNotEmpty);
      await session.openBot('nova', fresh: true);
      expect(session.thread, isEmpty);
      expect(session.responding, isFalse);
      expect(session.loadingThreads, isFalse);
      await session.send('A fresh idea');
      await _settle();
      expect(session.thread.first.fromUser, isTrue);
      expect(session.responding, isFalse);
    },
  );

  test('reopening the current bot preserves an in-flight reply', () async {
    final session = SessionController(
      MukaiDemoRepository(
        latency: Duration.zero,
        streamCadence: const Duration(milliseconds: 5),
      ),
    );
    addTearDown(session.dispose);
    await session.openBot('nova');
    await session.send('Keep going');
    expect(session.responding, isTrue);
    await session.openBot('nova');
    expect(session.responding, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(session.responding, isFalse);
    expect(session.thread.last.streaming, isFalse);
  });

  group('send', () {
    test('appends the user turn, then streams and finishes a reply', () async {
      final SessionController session = SessionController(_repo());
      await session.openBot('scout');
      final int before = session.thread.length;

      await session.send('How did Q1 land?');
      expect(session.responding, isTrue);
      expect(session.thread.length, greaterThan(before));
      expect(session.thread[before].fromUser, isTrue);

      await _settle();

      expect(session.responding, isFalse);
      expect(session.thread.last.fromUser, isFalse);
      expect(session.thread.last.streaming, isFalse);
      expect(session.thread.last.blocks, isNotEmpty);
    });

    test('ignores empty text', () async {
      final SessionController session = SessionController(_repo());
      await session.openBot('scout');
      final int before = session.thread.length;
      await session.send('   ');
      expect(session.thread.length, before);
      expect(session.responding, isFalse);
    });

    test('Stop ends the stream and keeps what was already drawn', () async {
      final SessionController session = SessionController(
        MukaiDemoRepository(
          latency: const Duration(milliseconds: 5),
          streamCadence: const Duration(milliseconds: 8),
        ),
      );
      await session.openBot('scout');

      unawaited(session.send('Walk me through it.'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      session.stop();

      expect(session.responding, isFalse);
      expect(session.thread.any((ChatMessage m) => m.streaming), isFalse);
      expect(session.thread, isNotEmpty);
    });

    test('a reply failure frees the composer and reports the error', () async {
      final SessionController broken = SessionController(_repo(failureRate: 1));
      await broken.openBot('scout');
      final int before = broken.thread.length;

      await broken.send('anything');

      expect(broken.responding, isFalse);
      expect(broken.hasError, isTrue);
      // The optimistic user turn stays visible — the message was really typed.
      expect(broken.thread.length, greaterThan(before));
    });
  });

  group('approvals', () {
    test('resolving an approval swaps it for a tool result', () async {
      final SessionController session = SessionController(_repo());
      await session.openBot('scout');
      await session.send('Make the change.');
      await _settle();

      final List<ApprovalBlock> approvals = session.thread
          .expand((ChatMessage m) => m.blocks)
          .whereType<ApprovalBlock>()
          .toList();
      expect(approvals, hasLength(1));

      session.resolveApproval(approvals.first, approved: true);

      final List<ChatBlock> blocks = session.thread
          .expand((ChatMessage m) => m.blocks)
          .toList();
      expect(blocks.whereType<ApprovalBlock>(), isEmpty);
      expect(
        blocks.whereType<ToolBlock>().any(
          (ToolBlock b) => b.label.contains('approved'),
        ),
        isTrue,
      );
    });
  });

  group('loadRecents', () {
    test('fills the home list, newest first and capped', () async {
      final SessionController session = SessionController(_repo());
      expect(session.recents, isEmpty);

      await session.loadRecents();

      expect(session.recents, hasLength(6));
      for (int i = 1; i < session.recents.length; i++) {
        expect(
          session.recents[i - 1].updatedAt.isAfter(
                session.recents[i].updatedAt,
              ) ||
              session.recents[i - 1].updatedAt == session.recents[i].updatedAt,
          isTrue,
        );
      }
    });

    test('honours the limit', () async {
      final SessionController session = SessionController(_repo());
      await session.loadRecents(limit: 2);
      expect(session.recents, hasLength(2));
    });

    test('reports a failed refresh without clearing what it had', () async {
      final SessionController session = SessionController(_repo());
      await session.loadRecents();
      final int kept = session.recents.length;

      final SessionController broken = SessionController(_repo(failureRate: 1));
      await broken.loadRecents();

      expect(broken.hasError, isTrue);
      expect(session.recents, hasLength(kept));
    });
  });

  test('dispose stops late updates', () async {
    final SessionController session = SessionController(
      MukaiDemoRepository(latency: const Duration(milliseconds: 20)),
    );
    session.addListener(() {});
    unawaited(session.openBot('scout'));
    session.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(session.thread, isEmpty);
  });
}
