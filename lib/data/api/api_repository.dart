import 'dart:convert';
import '../../core/approval_presentation.dart';

import '../../domain/models.dart';
import '../mukai_repository.dart';
import 'api_client.dart';

Map<String, dynamic> object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
String string(dynamic value, [String fallback = '']) =>
    value is String ? value : fallback;
DateTime date(dynamic value) =>
    DateTime.tryParse(string(value))?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);
String encoded(String value) => Uri.encodeComponent(value);

String _activityLabel(Map<String, dynamic> activity) {
  final running = activity['status'] == 'running';
  final action = string(activity['action']);
  final labels = <String, (String, String)>{
    'read_file': ('Reading a file', 'Read a file'),
    'write_file': ('Writing a file', 'Wrote a file'),
    'patch': ('Updating a file', 'Updated a file'),
    'search_files': ('Searching files', 'Searched files'),
    'list': ('Exploring the workspace', 'Explored the workspace'),
    'create_directory': ('Creating a folder', 'Created a folder'),
    'approval': ('Waiting for approval', 'Received your decision'),
    'clarification': ('Waiting for your answer', 'Received your answer'),
    'notify': ('Sending an update', 'Sent an update'),
    'view_image': ('Viewing an image', 'Viewed an image'),
  };
  final pair = labels[action];
  if (pair != null) return running ? pair.$1 : pair.$2;
  final tool = string(activity['tool']);
  if (tool == 'web_search') {
    return running ? 'Searching the web' : 'Searched the web';
  }
  if (tool == 'terminal') {
    return running ? 'Running a command' : 'Ran a command';
  }
  final name = tool.replaceAll('_', ' ').trim();
  return name.isEmpty
      ? 'Activity'
      : '${name[0].toUpperCase()}${name.substring(1)}';
}

class ApiRepository implements MukaiRepository {
  ApiRepository(this.api);
  final MukaiApiClient api;
  List<MukaiWorkspace> workspaces = [];
  String? workspaceId;
  int _refreshGeneration = 0;
  List<MukaiBot> _bots = [];
  List<Conversation> allConversations = [];
  List<Map<String, dynamic>> providers = [];
  Map<String, dynamic> approvals = {};
  final Map<String, List<Map<String, dynamic>>> _history = {};

  @override
  MukaiWorkspace get workspace =>
      workspaces.where((w) => w.id == workspaceId).firstOrNull ??
      (workspaces.isEmpty
          ? const MukaiWorkspace(
              id: '',
              name: 'Your workspace',
              kind: 'Workspace',
              tagline: 'A little momentum, every day.',
            )
          : workspaces.first);
  @override
  List<MukaiBot> get bots => _bots;
  @override
  MukaiBot botById(String id) =>
      bots.where((b) => b.id == id).firstOrNull ??
      const MukaiBot(
        id: '',
        name: 'Mukai',
        role: 'Your companion',
        mascot: 'mukai-logo',
        identity: BotIdentity.mukai,
        running: false,
      );

  @override
  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final requestedWorkspace = workspaceId;
    final items = objects(await api.request('/workspaces'));
    if (generation != _refreshGeneration || requestedWorkspace != workspaceId) {
      return;
    }
    final nextWorkspaces = items
        .map(
          (w) => MukaiWorkspace(
            id: string(w['id']),
            name: string(w['name']),
            kind: w['computer'] == 'qemu'
                ? 'Cloud workspace'
                : 'Folder workspace',
            tagline: 'A little momentum, every day.',
          ),
        )
        .toList();
    final selected = nextWorkspaces.any((w) => w.id == requestedWorkspace)
        ? requestedWorkspace
        : nextWorkspaces.firstOrNull?.id;
    if (selected == null) {
      workspaces = nextWorkspaces;
      workspaceId = null;
      _bots = [];
      allConversations = [];
      return;
    }
    final query = 'workspaceId=${encoded(selected)}';
    final data = await Future.wait([
      api.request('/bots?$query'),
      api.request('/conversations?$query'),
      api.request('/providers'),
      api.request('/approvals?$query'),
      api.request('/conversations?$query&kind=private'),
      api.request('/conversations?$query&kind=bot'),
    ]);
    if (generation != _refreshGeneration || requestedWorkspace != workspaceId) {
      return;
    }
    workspaces = nextWorkspaces;
    workspaceId = selected;
    providers = objects(data[2]);
    _bots = objects(data[0]).map(botFromJson).toList()
      ..sort(
        (a, b) => a.isMain == b.isMain
            ? a.name.compareTo(b.name)
            : a.isMain
            ? -1
            : 1,
      );
    final all = <String, Map<String, dynamic>>{};
    for (final c in [
      ...objects(data[1]),
      ...objects(data[4]),
      ...objects(data[5]),
    ]) {
      all[string(c['id'])] = c;
    }
    allConversations = all.values.map(conversationFromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    providers = objects(data[2]);
    approvals = object(data[3]);
  }

  MukaiBot botFromJson(Map<String, dynamic> b) {
    final avatar = string(b['avatar'], 'mukai-logo');
    final resolved = switch (avatar) {
      'scout' => 'muka-mascot-2-blue',
      'atlas' => 'muka-mascot-1-green',
      'nova' => 'muka-mascot-3-purple',
      _ => avatar,
    };
    return MukaiBot(
      id: string(b['id']),
      name: string(b['name'], 'Mukai'),
      role: string(b['role']),
      mascot: resolved,
      identity: resolved.contains('green')
          ? BotIdentity.atlas
          : resolved.contains('purple')
          ? BotIdentity.nova
          : resolved.contains('blue')
          ? BotIdentity.scout
          : BotIdentity.mukai,
      isMain: b['isMain'] == true,
      running: false,
      modelLabel: string(b['model'], 'Workspace default'),
    );
  }

  Conversation conversationFromJson(Map<String, dynamic> c) {
    final ids = (c['botIds'] as List? ?? []).whereType<String>().toList();
    return Conversation(
      id: string(c['id']),
      title: string(c['name'], 'Conversation'),
      botId: string(c['ownerBotId'], ids.firstOrNull ?? ''),
      botIds: ids,
      kind: string(c['kind'], 'private'),
      isWorking: c['isWorking'] == true,
      description: string(c['description']),
      preview: string(c['description']),
      updatedAt: date(c['updatedAt']),
    );
  }

  @override
  List<Conversation> conversationsFor(String botId) => allConversations
      .where((c) => c.kind == 'private' && c.botId == botId)
      .toList();
  @override
  List<Conversation> recentConversations({int? limit = 6}) => allConversations
      .where((c) => c.kind == 'private' || c.kind == 'bot')
      .take(limit ?? allConversations.length)
      .toList();
  String root(String botId, String? conversationId) => conversationId == null
      ? '/bots/${encoded(botId)}'
      : '/conversations/${encoded(conversationId)}';
  String conversationKey(String botId, String? conversationId) =>
      conversationId ?? 'bot-$botId';

  Future<String> createConversation(String botId) async => string(
    object(
      await api.request(
        '/bots/${encoded(botId)}/conversations',
        method: 'POST',
      ),
    )['id'],
  );
  @override
  Future<List<ChatMessage>> loadThread(
    String botId, {
    String? conversationId,
  }) async {
    final key = conversationKey(botId, conversationId);
    final selectedWorkspace = workspace.id;
    final rows = objects(
      await api.request('${root(botId, conversationId)}/messages'),
    );
    _history[key] = rows;
    final pending = object(
      await api.request('/approvals?workspaceId=${encoded(selectedWorkspace)}'),
    );
    if (workspace.id == selectedWorkspace) approvals = pending;
    return rows.map((row) => messageFromJson(row, key)).toList();
  }

  ChatMessage messageFromJson(Map<String, dynamic> m, String conversationId) {
    final activities = objects(m['activity']);
    final blocks = <ChatBlock>[];
    final parts = objects(m['parts']);
    final hasProcess = parts.any((p) => p['type'] != 'text');
    final answerIds = <String>{};
    if (hasProcess &&
        parts.isNotEmpty &&
        parts.last['type'] == 'text' &&
        (m['status'] == 'complete' || parts.last['final'] == true)) {
      var start = parts.length - 1;
      while (start > 0 && parts[start - 1]['type'] == 'text') {
        start--;
      }
      for (final part in parts.skip(start)) {
        answerIds.add(string(part['id']));
      }
      var first = parts[start];
      while (string(first['continuationOf']).isNotEmpty) {
        final previous = parts
            .where(
              (p) => p['type'] == 'text' && p['id'] == first['continuationOf'],
            )
            .firstOrNull;
        if (previous == null || !answerIds.add(string(previous['id']))) break;
        first = previous;
      }
    }

    void activity(Map<String, dynamic> a) {
      final delegation = object(a['delegation']);
      if (delegation.isNotEmpty) {
        blocks.add(
          SubBotBlock(
            botId: string(delegation['botId']),
            status: string(delegation['status'], string(a['status'])),
            result: string(a['summary']),
          ),
        );
      } else {
        String? preview;
        if (a['status'] == 'complete') {
          if ((a['tool'] == 'image' && a['action'] == 'view') ||
              (a['tool'] == 'media' && a['action'] == 'view_image')) {
            preview = 'mukai-activity:${string(a['id'])}';
          } else if (['browser', 'computer_use'].contains(a['tool']) &&
              a['action'] == 'screenshot') {
            try {
              final id = string(
                object(jsonDecode(string(a['summary'])))['artifactId'],
              );
              if (RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(id)) {
                preview = 'mukai://artifact/$id';
              }
            } catch (_) {}
          }
        }
        blocks.add(
          ToolBlock(
            id: string(a['id']),
            previewHref: preview,
            label: _activityLabel(a),
            detail:
                '${string(a['tool'])} · ${string(a['action'])}\n\n${string(a['summary'], string(a['path']))}'
                    .trim(),
            state: a['status'] == 'running'
                ? ToolState.running
                : a['status'] == 'complete'
                ? ToolState.done
                : ToolState.error,
          ),
        );
      }
    }

    if (parts.isNotEmpty) {
      for (final p in parts) {
        if (p['type'] == 'text' || p['type'] == 'steering') {
          blocks.add(
            TextBlock(
              string(p['text']),
              id: string(p['id']),
              commentary: hasProcess && !answerIds.contains(string(p['id'])),
            ),
          );
        }
        if (p['type'] == 'reasoning' && string(p['text']).isNotEmpty) {
          blocks.add(
            ToolBlock(
              id: string(p['id']),
              label: 'Reasoning',
              detail: string(p['text']),
              state: p['state'] == 'streaming'
                  ? ToolState.running
                  : ToolState.done,
            ),
          );
        }
        if (p['type'] == 'compaction') {
          final state = string(p['state']);
          blocks.add(
            CompactionBlock(
              id: string(p['id']),
              state: state == 'compacting' && m['status'] != 'streaming'
                  ? 'interrupted'
                  : state,
              before: p['tokensBefore'] is num
                  ? (p['tokensBefore'] as num).toInt()
                  : 0,
              after: p['tokensAfter'] is num
                  ? (p['tokensAfter'] as num).toInt()
                  : null,
            ),
          );
        }
        if (p['type'] == 'tool') {
          final a = activities
              .where((a) => a['id'] == p['activityId'])
              .firstOrNull;
          if (a != null) {
            activity(a);
          } else {
            blocks.add(
              ToolBlock(
                id: string(p['id']),
                label: m['status'] == 'streaming'
                    ? 'Calling tool…'
                    : 'Tool result unavailable',
                detail:
                    'The saved tool result is unavailable for this message.',
                state: m['status'] == 'streaming'
                    ? ToolState.running
                    : ToolState.error,
              ),
            );
          }
        }
      }
    } else {
      if (string(m['reasoning']).isNotEmpty) {
        blocks.add(
          ToolBlock(
            id: 'legacy-reasoning',
            label: 'Reasoning',
            detail: string(m['reasoning']),
            state: m['status'] == 'streaming'
                ? ToolState.running
                : ToolState.done,
          ),
        );
      }
      if (string(m['content']).isNotEmpty) {
        blocks.add(TextBlock(string(m['content'])));
      }
      for (final a in activities) {
        activity(a);
      }
    }
    for (final attachment in objects(m['attachments'])) {
      blocks.add(
        LinkBlock(
          title: string(attachment['name']),
          image:
              attachment['kind'] == 'image' ||
              string(attachment['mediaType']).startsWith('image/'),
          url: 'mukai-attachment:${string(attachment['id'])}',
        ),
      );
    }
    for (final a in objects(approvals['pending'])) {
      if (a['messageId'] == m['id'] ||
          objects(a['blockedParents']).any(
            (parent) =>
                parent['messageId'] == m['id'] &&
                parent['conversationId'] == conversationId,
          )) {
        blocks.add(approvalFromJson(a));
      }
    }
    return ChatMessage(
      id: string(m['id']),
      conversationId: conversationId,
      fromUser: m['role'] == 'user',
      at: date(m['createdAt']),
      botId: string(m['botId']),
      blocks: blocks,
      streaming: m['status'] == 'streaming',
      startedAt: DateTime.tryParse(string(m['startedAt'])),
      finishedAt: DateTime.tryParse(string(m['finishedAt'])),
      saved: m['saved'] == true,
      status: string(m['status']),
      requestId: string(m['requestId']),
      error: m['error'] as String?,
    );
  }

  ApprovalBlock approvalFromJson(Map<String, dynamic> a) {
    final ask = a['ask'] is Map ? object(a['ask']) : null;
    return ApprovalBlock(
      id: string(a['id']),
      toolName: string(a['toolName']),
      reason: string(ask?['question']).trim().isNotEmpty
          ? string(ask?['question'])
          : approvalDetails(a['input'], object(a['presentation'])),
      fullAccessAvailable: false,
      ask: ask,
      botName: string(a['botName']),
      notice: string(a['reviewNotice']),
    );
  }

  Stream<List<ChatMessage>> streamReply({
    required String botId,
    required String text,
    String? conversationId,
    required String requestId,
    List<String> attachmentIds = const [],
    bool space = false,
    String? retryMessageId,
  }) async* {
    final key = conversationKey(botId, conversationId);
    final history = _history.putIfAbsent(key, () => []);
    void upsert(dynamic value) {
      final m = object(value);
      if (m.isEmpty) return;
      final index = history.indexWhere((v) => v['id'] == m['id']);
      if (index < 0) {
        history.add(m);
      } else {
        history[index] = m;
      }
    }

    await for (final event in api.events(
      retryMessageId == null
          ? '${root(botId, conversationId)}/chat'
          : '/conversations/${encoded(conversationId ?? 'bot-$botId')}/retry',
      retryMessageId != null
          ? {'messageId': retryMessageId}
          : {
              'requestId': requestId,
              'text': text,
              'attachmentIds': attachmentIds,
              if (space) 'botId': botId.isEmpty ? null : botId,
            },
    )) {
      final type = event['type'];
      if (type == 'start') {
        upsert(event['user']);
        upsert(event['assistant']);
      }
      if (type == 'done' || type == 'error') upsert(event['message']);
      final m = history.where((m) => m['id'] == event['id']).firstOrNull;
      if (m != null) {
        if (type == 'delta') {
          m['content'] = string(m['content']) + string(event['text']);
          final parts = objects(m['parts']);
          final id = event['partId'];
          if (id != null) {
            final i = parts.indexWhere((p) => p['id'] == id);
            if (i < 0) {
              parts.add({
                'id': id,
                'type': 'text',
                'text': string(event['text']),
              });
            } else {
              parts[i]['text'] =
                  string(parts[i]['text']) + string(event['text']);
            }
            m['parts'] = parts;
          }
        }
        if (type == 'reasoning') {
          m['reasoning'] = string(m['reasoning']) + string(event['text']);
        }
        if (type == 'part') {
          final parts = objects(m['parts']);
          final p = object(event['part']);
          final i = parts.indexWhere((v) => v['id'] == p['id']);
          if (i < 0) {
            parts.add(p);
          } else {
            parts[i] = p;
          }
          m['parts'] = parts;
        }
        if (type == 'activity') {
          final all = objects(m['activity']);
          final a = object(event['activity']);
          final i = all.indexWhere((v) => v['id'] == a['id']);
          if (i < 0) {
            all.add(a);
          } else {
            all[i] = a;
          }
          m['activity'] = all;
          if (event['changes'] != null) m['changes'] = event['changes'];
        }
        if (type == 'context') m['contextUsage'] = event['usage'];
      }
      if (type == 'approval') {
        approvals = object(
          await api.request('/approvals?workspaceId=${encoded(workspace.id)}'),
        );
      }
      yield history.map((m) => messageFromJson(m, key)).toList();
    }
  }

  List<ChatMessage> currentThread(String botId, String? conversationId) {
    final key = conversationKey(botId, conversationId);
    return (_history[key] ?? []).map((m) => messageFromJson(m, key)).toList();
  }

  @override
  Future<ChatActivity> loadActivity(
    String botId, {
    String? conversationId,
  }) async {
    final key = conversationKey(botId, conversationId);
    final artifacts = objects(
      await api.request('/conversations/${encoded(key)}/artifacts'),
    );
    final history = _history[key] ?? [];
    final activities = history.expand((m) => objects(m['activity'])).toList();
    return ChatActivity(
      bots: history
          .map((m) => string(m['botId']))
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList(),
      outputs: artifacts
          .map(
            (a) => ActivityOutput(
              name: string(a['name']),
              kind: string(a['mediaType'], 'Workspace file'),
              id: string(a['id']),
            ),
          )
          .toList(),
      changes: history
          .expand((m) => objects(m['changes']))
          .map(
            (c) => ActivityChange(
              file: string(c['path']).split('/').last,
              path: string(c['path']),
              added: (c['added'] as num?)?.toInt() ?? 0,
              removed: (c['removed'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(),
      links: activities
          .expand((a) => (a['serverUrls'] as List? ?? []).whereType<String>())
          .toSet()
          .map((url) => ActivityLink(title: url, state: 'Workspace server'))
          .toList(),
    );
  }

  @override
  Duration get streamCadence => Duration.zero;
  @override
  Future<List<ChatBlock>> generateReply({
    required String botId,
    required String text,
    required int turn,
  }) => throw UnsupportedError('Use the real response stream.');
}
