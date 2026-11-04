/// The seam between the UI and Mukai's data.
///
/// Every screen reads through this interface. Today it is served by
/// [MukaiDemoRepository]; an HTTP/WebSocket implementation backed by the local
/// Mukai backend (`127.0.0.1:47831`) drops in without touching a widget.
library;

import '../domain/models.dart';

abstract interface class MukaiRepository {
  MukaiWorkspace get workspace;
  List<MukaiBot> get bots;
  MukaiBot botById(String id);
  List<Conversation> conversationsFor(String botId);

  /// Most recently touched conversations across the whole workspace, newest
  /// first. A null limit returns all available private/bot conversations.
  List<Conversation> recentConversations({int? limit = 6});

  /// Refetch the workspace-level lists. Allowed to fail; the UI shows a retry.
  Future<void> refresh();

  Future<List<ChatMessage>> loadThread(String botId, {String? conversationId});
  Future<ChatActivity> loadActivity(String botId, {String? conversationId});

  /// Next assistant turn. The demo repo returns a script; the real repo calls a
  /// bot and streams blocks back.
  Future<List<ChatBlock>> generateReply({
    required String botId,
    required String text,
    required int turn,
  });

  /// How long a streamed block waits before appearing.
  Duration get streamCadence;
}

/// Thrown by repositories so the UI can show one consistent failure surface.
class MukaiDataException implements Exception {
  const MukaiDataException(this.message);
  final String message;

  @override
  String toString() => message;
}
