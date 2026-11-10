/// Domain layer — the entities Mukai talks about, with no dependency on
/// Flutter widgets, the backend, or how anything is painted.
///
/// Design-layer colour lives in `design/appearance.dart` (see the
/// [BotIdentityPalette] extension), so a bot entity never carries a hex value.
library;

import 'package:flutter/foundation.dart';

/// Which visual identity a bot wears. The palette mapping is presentation.
enum BotIdentity { scout, atlas, nova, mukai, neutral }

@immutable
class MukaiWorkspace {
  const MukaiWorkspace({
    required this.name,
    required this.tagline,
    required this.kind,
    this.id = 'default',
    this.timeZone,
  });

  final String id;
  final String? timeZone;
  final String name;
  final String tagline;

  /// "Folder workspace" or "Personal workspace".
  final String kind;
}

@immutable
class MukaiBot {
  const MukaiBot({
    required this.id,
    required this.name,
    required this.role,
    required this.mascot,
    required this.identity,
    this.isMain = false,
    this.running = true,
    this.modelLabel = 'Workspace default',
  });

  final String id;
  final String name;

  /// Required on every bot: "Main Bot/Orchestrator", "Project builder", ...
  final String role;

  /// Mascot asset id in `assets/mascots/`.
  final String mascot;
  final BotIdentity identity;

  /// The main bot carries the star and starts with every tool.
  final bool isMain;
  final bool running;
  final String modelLabel;
}

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.botId,
    required this.updatedAt,
    this.preview = '',
    this.kind = 'private',
    this.isWorking = false,
    this.description = '',
    this.botIds = const [],
    this.pursuitId,
    this.runId,
  });

  final String kind;
  final bool isWorking;
  final String description;
  final List<String> botIds;
  final String id;
  final String title;
  final String botId;
  final DateTime updatedAt;
  final String preview;
  final String? pursuitId, runId;
}

@immutable
class NotificationSource {
  const NotificationSource({
    required this.conversationId,
    required this.name,
    this.pursuitId,
    this.runId,
  });

  final String conversationId, name;
  final String? pursuitId, runId;
  bool get isRun => pursuitId != null && runId != null;
}

// ---------------------------------------------------------------------------
// Rich response blocks — the desktop `responseRichContent` vocabulary
// ---------------------------------------------------------------------------

@immutable
sealed class ChatBlock {
  const ChatBlock();
  String? get stableId => null;
  bool get isProcess => false;
}

class TextBlock extends ChatBlock {
  const TextBlock(this.text, {this.id, this.commentary = false});
  final bool commentary;
  @override
  bool get isProcess => commentary;
  final String? id;
  @override
  String? get stableId => id;
  final String text;
}

class SteeringBlock extends ChatBlock {
  const SteeringBlock(
    this.text, {
    required this.id,
    this.attachments = const [],
  });
  final String text, id;
  final List<LinkBlock> attachments;
  @override
  bool get isProcess => true;
  @override
  String get stableId => id;
}

class HeadingBlock extends ChatBlock {
  const HeadingBlock(this.text);
  final String text;
}

class BulletBlock extends ChatBlock {
  const BulletBlock(this.items);
  final List<String> items;
}

class ChartBlock extends ChatBlock {
  const ChartBlock({
    required this.title,
    required this.seriesLabel,
    required this.points,
    this.downloadable = true,
  });

  final String title;
  final String seriesLabel;
  final List<({String label, double value})> points;
  final bool downloadable;
}

class TableBlock extends ChatBlock {
  const TableBlock({required this.columns, required this.rows, this.summary});

  final List<String> columns;
  final List<List<String>> rows;
  final String? summary;
}

enum ToolState { running, done, error }

class ToolBlock extends ChatBlock {
  const ToolBlock({
    required this.label,
    required this.detail,
    required this.state,
    this.id,
    this.previewHref,
  });

  final String? previewHref;
  @override
  bool get isProcess => true;
  final String? id;
  @override
  String? get stableId => id;
  final String label;
  final String detail;
  final ToolState state;
}

class CompactionBlock extends ChatBlock {
  const CompactionBlock({
    required this.id,
    required this.state,
    required this.before,
    this.after,
  });
  final String id, state;
  final int before;
  final int? after;
  @override
  String? get stableId => id;
  @override
  bool get isProcess => true;
}

/// A pending human approval — the app never runs the tool until it is answered.
class ApprovalBlock extends ChatBlock {
  const ApprovalBlock({
    required this.toolName,
    required this.reason,
    required this.fullAccessAvailable,
    this.id,
    this.ask,
    this.botName,
    this.notice,
  });

  final String toolName;
  final String reason;
  final bool fullAccessAvailable;
  final String? id;
  final Map<String, dynamic>? ask;
  final String? botName;
  final String? notice;
}

/// A delegated sub-bot and where its result came back to.
class SubBotBlock extends ChatBlock {
  const SubBotBlock({required this.botId, required this.status, this.result});

  @override
  bool get isProcess => true;
  final String botId;
  final String status;
  final String? result;
}

class LinkBlock extends ChatBlock {
  const LinkBlock({
    required this.title,
    required this.url,
    this.state,
    this.image = false,
  });
  final bool image;
  final String title;
  final String url;
  final String? state;
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromUser,
    required this.blocks,
    required this.at,
    this.botId,
    this.streaming = false,
    this.saved = false,
    this.status = 'complete',
    this.requestId = '',
    this.error,
    this.startedAt,
    this.finishedAt,
    this.conversationId,
    this.notificationSource,
  });

  final String? conversationId;
  final NotificationSource? notificationSource;
  final DateTime? startedAt, finishedAt;
  final String id;
  final bool fromUser;
  final List<ChatBlock> blocks;
  final DateTime at;
  final String? botId;

  /// True while more blocks are still arriving for this message.
  final bool streaming;
  final bool saved;
  final String status;
  final String requestId;
  final String? error;

  ChatMessage copyWith({
    List<ChatBlock>? blocks,
    bool? streaming,
    bool? saved,
  }) => ChatMessage(
    id: id,
    fromUser: fromUser,
    blocks: blocks ?? this.blocks,
    at: at,
    botId: botId,
    saved: saved ?? this.saved,
    status: status,
    requestId: requestId,
    error: error,
    conversationId: conversationId,
    notificationSource: notificationSource,
    startedAt: startedAt,
    finishedAt: finishedAt,
    streaming: streaming ?? this.streaming,
  );
}

// ---------------------------------------------------------------------------
// Chat activity (desktop right rail)
// ---------------------------------------------------------------------------

@immutable
class ActivityLink {
  const ActivityLink({required this.title, required this.state});
  final String title;
  final String state;
}

@immutable
class ActivityOutput {
  const ActivityOutput({required this.name, required this.kind, this.id});
  final String name;
  final String kind;
  final String? id;
}

@immutable
class ActivityChange {
  const ActivityChange({
    required this.file,
    required this.path,
    required this.added,
    required this.removed,
  });

  final String file;
  final String path;
  final int added;
  final int removed;

  int get touched => added + removed;
}

@immutable
class ChatActivity {
  const ChatActivity({
    this.bots = const <String>[],
    this.links = const <ActivityLink>[],
    this.outputs = const <ActivityOutput>[],
    this.changes = const <ActivityChange>[],
  });

  final List<String> bots;
  final List<ActivityLink> links;
  final List<ActivityOutput> outputs;
  final List<ActivityChange> changes;

  int get total => bots.length + links.length + outputs.length + changes.length;

  bool get isEmpty => total == 0;
}
