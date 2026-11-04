/// Demo [MukaiRepository]: fixed fixtures plus fake latency and streaming.
///
/// Exists so the UI can be built and reviewed before this client has a
/// transport. Swap in a backend-backed implementation in `lib/data/api/` and
/// nothing above the repository changes.
library;

import 'dart:math' as math;

import '../mukai_repository.dart';
import '../../domain/models.dart';
import 'demo_fixtures.dart';

class MukaiDemoRepository implements MukaiRepository {
  MukaiDemoRepository({
    Duration latency = const Duration(milliseconds: 260),
    this.streamCadence = const Duration(milliseconds: 520),
    this.failureRate = 0,
    RandomOverride? random,
  }) : _latency = latency,
       _random = random ?? _defaultRandom;

  final Duration _latency;
  final RandomOverride _random;

  /// Set above 0 to exercise error states in the UI (0–1).
  final double failureRate;

  static final RandomOverride _defaultRandom = RandomOverride();

  @override
  final Duration streamCadence;

  @override
  MukaiWorkspace get workspace => DemoFixtures.workspace;

  @override
  List<MukaiBot> get bots => DemoFixtures.bots;

  @override
  MukaiBot botById(String id) =>
      bots.firstWhere((bot) => bot.id == id, orElse: () => bots.first);

  @override
  List<Conversation> conversationsFor(String botId) =>
      DemoFixtures.conversationsFor(botId);

  @override
  List<Conversation> recentConversations({int? limit = 6}) {
    final List<Conversation> all =
        <Conversation>[
          for (final MukaiBot bot in bots)
            ...DemoFixtures.conversationsFor(bot.id),
        ]..sort(
          (Conversation a, Conversation b) =>
              b.updatedAt.compareTo(a.updatedAt),
        );
    return limit == null || all.length <= limit ? all : all.sublist(0, limit);
  }

  @override
  Future<void> refresh() => _after<void>(() {});

  @override
  Future<List<ChatMessage>> loadThread(
    String botId, {
    String? conversationId,
  }) => _after(() => DemoFixtures.threadFor(botId));

  @override
  Future<ChatActivity> loadActivity(String botId, {String? conversationId}) =>
      _after(
        () => botId == 'scout'
            ? DemoFixtures.revenueActivity
            : DemoFixtures.idleActivity,
      );

  @override
  Future<List<ChatBlock>> generateReply({
    required String botId,
    required String text,
    required int turn,
  }) => _after(() => DemoFixtures.replyScript(text, turn: turn));

  Future<T> _after<T>(T Function() build) async {
    await Future<void>.delayed(_latency);
    if (failureRate > 0 && _random.next() < failureRate) {
      throw const MukaiDataException(
        'No provider is connected yet. Add one in Settings → Providers.',
      );
    }
    return build();
  }
}

/// Tiny injectable indirection so tests can force failures deterministically.
class RandomOverride {
  RandomOverride([this.forced, math.Random? random])
    : _random = random ?? math.Random();

  /// When set, [next] always returns this instead of drawing a value.
  final double? forced;
  final math.Random _random;

  double next() => forced ?? _random.nextDouble();
}
