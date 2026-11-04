/// Session state for the workspace + chat surface.
///
/// Deliberately transport-free: it only knows [MukaiRepository]. Async work is
/// guarded by a generation counter so a bot switch, a Stop, or a dispose can
/// never land a late update — the classic source of "widget disposed" crashes
/// in streaming chat UIs.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import '../data/api/api_client.dart';
import '../data/api/api_repository.dart';

import '../data/mukai_repository.dart';
import '../domain/models.dart';

class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController(this._repository) {
    if (remote != null) {
      WidgetsBinding.instance.addObserver(this);
      _startPolling();
      unawaited(refreshNotices());
    }
  }

  ApiRepository? get remote =>
      _repository is ApiRepository ? _repository : null;
  MukaiApiClient? get api => remote?.api;
  List<MukaiWorkspace> get workspaces => remote?.workspaces ?? [workspace];
  String? get conversationId => _conversationId;
  bool _space = false;
  bool get isSpace => _space;
  bool readOnly = false;
  Timer? _pollTimer;
  bool _polling = false;
  bool _foreground = true;
  bool _chatVisible = true;
  void showWorkspace() {
    _chatVisible = false;
    if (remote != null) loadRecents();
  }

  StreamSubscription<List<ChatMessage>>? _liveSubscription;
  Completer<void>? _sendCompletion;
  Future<void> _cancelLiveSubscription() async {
    _generation++;
    final subscription = _liveSubscription;
    _liveSubscription = null;
    if (_sendCompletion?.isCompleted == false) _sendCompletion!.complete();
    _sendCompletion = null;
    final cancellation = subscription?.cancel();
    api?.cancelEvents();
    if (cancellation != null) unawaited(cancellation.catchError((Object _) {}));
  }

  final List<Map<String, dynamic>> attachments = [];
  List<Map<String, dynamic>> followups = [];
  final Map<String, String> drafts = {};
  final Map<String, ({String text, String id})> _uncertainRequests = {};
  void _reconcileDraft(String key, List<ChatMessage> messages) {
    final pending = _uncertainRequests[key];
    if (pending != null &&
        messages.any((m) => m.requestId == pending.id && m.fromUser)) {
      _uncertainRequests.remove(key);
      if (drafts[key] == pending.text) drafts.remove(key);
    }
  }

  String get draftKey => _conversationId ?? 'bot-${_bot?.id ?? ''}';
  List<ApprovalBlock> get pendingApprovals {
    if (readOnly) return [];
    if (remote == null) {
      return _thread
          .expand((m) => m.blocks)
          .whereType<ApprovalBlock>()
          .toList();
    }
    final conversation = _conversationId ?? 'bot-${bot.id}';
    return objects(remote!.approvals['pending'])
        .where(
          (a) =>
              a['conversationId'] == conversation ||
              objects(
                a['blockedParents'],
              ).any((p) => p['conversationId'] == conversation),
        )
        .map(remote!.approvalFromJson)
        .toList();
  }

  String get approvalMode => string(remote?.approvals['mode'], 'full-access');
  List<String> get modelOptions => [
    'Workspace default',
    for (final p in remote?.providers ?? <Map<String, dynamic>>[])
      for (final m in objects(p['models']))
        '${string(p['name'])} / ${string(m['id'])}',
  ];

  int updateCount = 0, unreadUpdateCount = 0;
  Map<String, dynamic> aiActivity = {};
  String? _noticeWorkspace, _noticeInFlight;
  int _noticeGeneration = 0;

  Future<void> refreshNotices() async {
    if (_disposed || api == null || !_foreground || workspace.id.isEmpty) {
      return;
    }
    final id = workspace.id;
    if (_noticeWorkspace != id) {
      _noticeWorkspace = id;
      updateCount = 0;
      unreadUpdateCount = 0;
      aiActivity = {};
    }
    if (_noticeInFlight == id) return;
    final generation = ++_noticeGeneration;
    _noticeInFlight = id;
    Future<dynamic> read(String path) async {
      try {
        return await api!.request(path);
      } catch (_) {
        return null;
      }
    }

    final values = await Future.wait([
      read('/notifications?workspaceId=${encoded(id)}&offset=0'),
      read('/ai-activity'),
    ]);
    if (_disposed || generation != _noticeGeneration || workspace.id != id) {
      return;
    }
    _noticeInFlight = null;
    if (values[0] is Map) {
      final inbox = object(values[0]);
      updateCount = inbox['total'] is num ? (inbox['total'] as num).toInt() : 0;
      unreadUpdateCount = inbox['unread'] is num
          ? (inbox['unread'] as num).toInt()
          : 0;
    }
    aiActivity = values[1] is Map
        ? object(values[1])
        : {}; // Never retain a stale recovery banner offline.
    _emit();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshLive();
      refreshNotices();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _startPolling();
      refreshLive();
      refreshNotices();
    } else {
      _pollTimer?.cancel();
    }
  }

  Future<void> refreshLive() async {
    if (_disposed || remote == null || _polling || !_foreground || _loading) {
      return;
    }
    _polling = true;
    final generation = _generation;
    try {
      if (!_chatVisible) {
        await remote!.refresh();
        if (_isCurrent(generation)) {
          _recents = remote!.recentConversations();
          _emit();
        }
        return;
      }
      if (_bot == null) {
        await remote!.refresh();
        if (_isCurrent(generation)) _recents = remote!.recentConversations();
      }
      if (_bot != null && !_responding) {
        final thread = await remote!.loadThread(
          bot.id,
          conversationId: _conversationId,
        );
        final pending = readOnly
            ? <Map<String, dynamic>>[]
            : objects(
                await api!.request(
                  '${remote!.root(bot.id, _conversationId)}/followups',
                ),
              );
        if (_isCurrent(generation)) {
          _thread = thread;
          _reconcileDraft(draftKey, thread);
          followups = pending;
        }
      } else {
        remote!.approvals = object(
          await api!.request('/approvals?workspaceId=${encoded(workspace.id)}'),
        );
        if (_bot != null && _isCurrent(generation)) {
          _thread = remote!.currentThread(bot.id, _conversationId);
        }
      }
      if (_bot != null && _isCurrent(generation)) {
        _activity = await remote!.loadActivity(
          bot.id,
          conversationId: _conversationId,
        );
      }
      if (_isCurrent(generation)) {
        _error = null;
        _emit();
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        _error = error.toString();
        _emit();
      }
    } finally {
      _polling = false;
    }
  }

  void selectSpaceBot(String id) {
    if (!_space || responding) return;
    _bot = _repository.botById(id);
    _emit();
  }

  Future<void> selectWorkspace(String id) async {
    if (remote == null || id == workspace.id) return;
    _stopStream();
    await _cancelLiveSubscription();
    _bot = null;
    _thread = [];
    _recents = [];
    _activity = const ChatActivity();
    attachments.clear();
    followups = [];
    _responding = false;
    remote!.workspaceId = id;
    updateCount = 0;
    unreadUpdateCount = 0;
    aiActivity = {};
    _emit();
    await loadRecents();
    await refreshNotices();
  }

  Future<void> _mutation(
    Future<dynamic> Function() request,
    void Function(dynamic) apply, {
    bool refresh = false,
  }) async {
    final generation = _generation;
    try {
      final value = await request();
      if (!_isCurrent(generation)) return;
      apply(value);
      if (refresh) await refreshLive();
      if (_isCurrent(generation)) _emit();
    } catch (error) {
      if (_isCurrent(generation)) {
        _error = error.toString();
        _emit();
      }
    }
  }

  Future<void> setApprovalMode(String mode) async {
    if (api == null) return;
    final path = '/approvals?workspaceId=${encoded(workspace.id)}';
    await _mutation(
      () => api!.request(path, method: 'PUT', body: {'mode': mode}),
      (value) => remote!.approvals = object(value),
    );
  }

  Future<void> setModel(String label) async {
    if (api == null || _bot == null || bot.id.isEmpty) return;
    String? providerId;
    String? model;
    for (final p in remote!.providers) {
      for (final m in objects(p['models'])) {
        if ('${string(p['name'])} / ${string(m['id'])}' == label) {
          providerId = string(p['id']);
          model = string(m['id']);
        }
      }
    }
    final path = '/bots/${encoded(bot.id)}/model';
    await _mutation(
      () => api!.request(
        path,
        method: 'PUT',
        body: {
          'providerId': providerId,
          'model': model,
          'supportsImages': null,
          'contextWindowTokens': null,
          'reasoningEffort': null,
        },
      ),
      (value) => _bot = remote!.botFromJson(object(value)),
    );
  }

  Future<void> addAttachment(String name, List<int> bytes) async {
    if (api == null || _bot == null || _space || readOnly) return;
    if (bytes.length > 10 * 1024 * 1024) {
      throw const ApiException('Files must be 10 MB or smaller.');
    }
    if (attachments.length >= 4) {
      throw const ApiException('Attach up to four files per message.');
    }
    final generation = _generation;
    final value = object(
      await api!.upload(
        '${remote!.root(bot.id, _conversationId)}/attachments',
        name,
        bytes,
      ),
    );
    if (_isCurrent(generation)) {
      attachments.add(value);
      _emit();
    }
  }

  Future<void> removeAttachment(String id) async {
    if (api == null) return;
    await _mutation(
      () => api!.request('/attachments/${encoded(id)}', method: 'DELETE'),
      (_) => attachments.removeWhere((a) => a['id'] == id),
    );
  }

  Future<void> updateFollowup(String id, String action, {String? text}) async {
    if (api == null) return;
    final path = '${remote!.root(bot.id, _conversationId)}/followups';
    await _mutation(
      () => api!.request(
        path,
        method: 'PUT',
        body: {'id': id, 'action': action, 'text': ?text},
      ),
      (value) => followups = objects(value),
    );
  }

  Future<void> saveMessage(ChatMessage message) async {
    if (api == null) return;
    final path =
        '/conversations/${encoded(_conversationId ?? 'bot-${bot.id}')}/saved';
    await _mutation(
      () => api!.request(
        path,
        method: 'PUT',
        body: {'messageId': message.id, 'saved': !message.saved},
      ),
      (_) {},
      refresh: true,
    );
  }

  Future<void> answerApproval(ApprovalBlock approval, String answer) async {
    if (api == null || approval.id == null) return;
    final path =
        '/approvals/${encoded(approval.id!)}?workspaceId=${encoded(workspace.id)}';
    await _mutation(
      () => api!.request(path, method: 'POST', body: {'answer': answer}),
      (value) => remote!.approvals = object(value),
      refresh: true,
    );
  }

  final MukaiRepository _repository;

  bool _disposed = false;
  int _generation = 0;
  int _workspaceGeneration = 0;
  Timer? _streamTimer;

  MukaiBot? _bot;
  List<ChatMessage> _thread = const <ChatMessage>[];
  List<Conversation> _conversations = const <Conversation>[];
  List<Conversation> _recents = const <Conversation>[];
  ChatActivity _activity = const ChatActivity();
  String? _conversationId;
  bool _loading = false;
  bool _responding = false;
  String? _error;
  int _turn = 0;

  // --- Read-only surface ----------------------------------------------------

  MukaiWorkspace get workspace => _repository.workspace;
  List<MukaiBot> get bots => _repository.bots;
  MukaiBot get bot =>
      _bot ??
      (bots.isNotEmpty
          ? bots.first
          : const MukaiBot(
              id: '',
              name: 'Mukai',
              role: 'Your companion',
              mascot: 'mukai-logo',
              identity: BotIdentity.mukai,
              running: false,
            ));
  List<ChatMessage> get thread => _thread;
  List<Conversation> get conversations => _conversations;

  /// Workspace-wide recents, as shown on the home screen.
  List<Conversation> get recents => _recents;
  ChatActivity get activity => _activity;
  bool get loadingThreads => _loading;
  bool get responding =>
      _responding || (remote != null && _thread.any((m) => m.streaming));
  String? get error => _error;
  bool get hasError => _error != null;

  @override
  void dispose() {
    _disposed = true;
    _streamTimer?.cancel();
    _pollTimer?.cancel();
    _cancelLiveSubscription();
    if (remote != null) {
      WidgetsBinding.instance.removeObserver(this);
      api!.close();
    }
    super.dispose();
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  // --- Navigation between bots ---------------------------------------------

  /// Loads a bot's thread and activity rail. Safe to call repeatedly.
  Future<void> openBot(
    String botId, {
    String? conversationId,
    bool fresh = false,
    bool space = false,
    bool viewOnly = false,
  }) async {
    _chatVisible = true;
    final MukaiBot next = _repository.botById(botId);
    final bool sameBot =
        !fresh &&
        _bot?.id == botId &&
        _thread.isNotEmpty &&
        (remote != null
            ? conversationId == _conversationId
            : (conversationId == null || conversationId == _conversationId));
    if (sameBot && _space == space && readOnly == viewOnly) return;
    await _cancelLiveSubscription();
    if (_disposed) return;
    _space = space;
    readOnly = viewOnly;
    attachments.clear();
    followups = [];
    _bot = next;
    _conversations = _repository.conversationsFor(botId);
    _conversationId = fresh
        ? null
        : conversationId ??
              (remote != null
                  ? null
                  : (_conversations.isEmpty ? null : _conversations.first.id));
    _error = null;
    _turn = 0;
    _stopStream();
    _responding = false;

    _thread = const <ChatMessage>[];
    _activity = const ChatActivity();
    _loading = true;
    _emit();

    final int generation = ++_generation;
    try {
      if (fresh && remote != null) {
        final created = await remote!.createConversation(botId);
        if (!_isCurrent(generation)) return;
        _conversationId = created;
      }
      final selectedConversation = _conversationId;
      final thread = fresh && remote == null
          ? <ChatMessage>[]
          : await _repository.loadThread(
              botId,
              conversationId: selectedConversation,
            );
      final activity = await _repository.loadActivity(
        botId,
        conversationId: selectedConversation,
      );
      final pendingAttachments = remote != null && !viewOnly
          ? objects(
              await api!.request(
                '${remote!.root(botId, selectedConversation)}/attachments',
              ),
            )
          : <Map<String, dynamic>>[];
      final pendingFollowups = remote != null && !viewOnly
          ? objects(
              await api!.request(
                '${remote!.root(botId, selectedConversation)}/followups',
              ),
            )
          : <Map<String, dynamic>>[];
      if (!_isCurrent(generation)) return;
      _thread = thread;
      _activity = activity;
      attachments.addAll(pendingAttachments);
      followups = pendingFollowups;
    } on MukaiDataException catch (failure) {
      if (!_isCurrent(generation)) return;
      _error = failure.message;
    } catch (failure) {
      if (!_isCurrent(generation)) return;
      _error = 'The workspace could not be reached. $_describe(failure)';
    } finally {
      if (_isCurrent(generation)) {
        _loading = false;
        _emit();
      }
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  String _describe(Object error) => error.toString();

  // --- Sending --------------------------------------------------------------

  /// Optimistic send followed by a streamed reply. Ignored while a reply is in
  /// flight, matching how the desktop composer disables itself.
  Future<void> send(String rawText) async {
    final String text = rawText.trim();
    if (_loading || (text.isEmpty && attachments.isEmpty) || readOnly) return;
    if (remote != null) {
      await _sendLive(text);
      return;
    }
    if (_responding) return;

    _error = null;
    _thread = <ChatMessage>[
      ..._thread,
      ChatMessage(
        id: 'user-${DateTime.now().microsecondsSinceEpoch}',
        fromUser: true,
        at: DateTime.now(),
        blocks: <ChatBlock>[TextBlock(text)],
      ),
    ];
    _responding = true;
    _emit();

    final int generation = ++_generation;
    final String replyId = 'bot-${DateTime.now().microsecondsSinceEpoch}';
    final String botId = bot.id;

    List<ChatBlock> blocks;
    try {
      blocks = await _repository.generateReply(
        botId: botId,
        text: text,
        turn: ++_turn,
      );
    } on MukaiDataException catch (failure) {
      if (!_isCurrent(generation)) return;
      _responding = false;
      _error = failure.message;
      _emit();
      return;
    } catch (failure) {
      if (!_isCurrent(generation)) return;
      _responding = false;
      _error = 'That response could not be completed. $_describe(failure)';
      _emit();
      return;
    }

    if (!_isCurrent(generation)) return;
    _thread = <ChatMessage>[
      ..._thread,
      ChatMessage(
        id: replyId,
        fromUser: false,
        botId: botId,
        at: DateTime.now(),
        streaming: true,
        blocks: const <ChatBlock>[],
      ),
    ];
    _emit();
    _reveal(replyId, blocks, generation);
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (remote != null && !readOnly && !responding) {
      await _sendLive('', retryMessageId: message.id);
    }
  }

  Future<void> _sendLive(String text, {String? retryMessageId}) async {
    if (_bot == null) return;
    if (_responding || _thread.any((m) => m.streaming)) {
      final key = draftKey;
      final ids = attachments.map((a) => string(a['id'])).toList();
      final path = '${remote!.root(bot.id, _conversationId)}/followups';
      final body = {
        'id': newRequestId(),
        'text': text,
        'attachmentIds': ids,
        if (_space) 'botId': bot.id.isEmpty ? null : bot.id,
      };
      await _mutation(() => api!.request(path, method: 'POST', body: body), (
        value,
      ) {
        followups = objects(value);
        attachments.removeWhere((a) => ids.contains(a['id']));
        if (drafts[key] == text || drafts[key]?.isEmpty == true) {
          drafts.remove(key);
        }
      });
      return;
    }
    _error = null;
    _responding = true;
    _emit();
    final generation = ++_generation;
    final sentAttachments = attachments.map((a) => string(a['id'])).toList();
    final key = draftKey;
    final pending = _uncertainRequests[key];
    final requestId = pending?.text == text ? pending!.id : newRequestId();
    _uncertainRequests[key] = (text: text, id: requestId);
    bool accepted = false;
    final complete = Completer<void>();
    _sendCompletion = complete;
    _liveSubscription = remote!
        .streamReply(
          botId: bot.id,
          text: text,
          conversationId: _conversationId,
          requestId: requestId,
          attachmentIds: sentAttachments,
          space: _space,
          retryMessageId: retryMessageId,
        )
        .listen(
          (thread) {
            if (!_isCurrent(generation)) return;
            _thread = thread;
            accepted =
                accepted ||
                thread.any((m) => m.requestId == requestId && m.fromUser);
            if (accepted) _uncertainRequests.remove(key);
            final failure = thread
                .where((m) => m.status == 'failed')
                .lastOrNull;
            if (failure?.error != null) _error = failure!.error;
            attachments.removeWhere((a) => sentAttachments.contains(a['id']));
            _emit();
          },
          onError: (Object error) {
            if (_isCurrent(generation)) {
              _responding = false;
              _error = error.toString();
              if (!accepted && (drafts[key]?.isEmpty ?? true)) {
                drafts[key] = text;
              }
              _emit();
              refreshLive();
            }
            if (!complete.isCompleted) complete.complete();
          },
          onDone: () {
            if (_isCurrent(generation)) {
              _responding = false;
              _emit();
              refreshLive();
              loadRecents();
            }
            if (!complete.isCompleted) complete.complete();
          },
        );
    await complete.future;
  }

  void _reveal(String replyId, List<ChatBlock> blocks, int generation) {
    int delivered = 0;
    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(_repository.streamCadence, (Timer timer) {
      if (!_isCurrent(generation)) {
        timer.cancel();
        return;
      }
      delivered++;
      _thread = <ChatMessage>[
        for (final ChatMessage message in _thread)
          if (message.id == replyId)
            message.copyWith(
              blocks: blocks.take(delivered).toList(),
              streaming: delivered < blocks.length,
            )
          else
            message,
      ];
      _emit();

      if (delivered >= blocks.length) {
        timer.cancel();
        _streamTimer = null;
        _responding = false;
        _activity = _activityWithReply();
        _emit();
      }
    });
  }

  ChatActivity _activityWithReply() {
    const int cap = 6;
    final List<ActivityOutput> outputs = <ActivityOutput>[
      const ActivityOutput(name: 'reply-summary.md', kind: 'Workspace file'),
      ..._activity.outputs,
    ];
    return ChatActivity(
      bots: _activity.bots,
      links: _activity.links,
      outputs: outputs.take(cap).toList(),
      changes: _activity.changes,
    );
  }

  /// Mirrors Stop: cancels the continuation, keeps saved progress.
  void stop() {
    if (remote != null) {
      _stopLive();
      return;
    }
    _stopStream();
    _responding = false;
    _thread = <ChatMessage>[
      for (final ChatMessage message in _thread)
        if (message.streaming) message.copyWith(streaming: false) else message,
    ];
    _emit();
  }

  Future<void> _stopLive() async {
    if (api == null) return;
    final path = '${remote!.root(bot.id, _conversationId)}/stop';
    await _mutation(() => api!.request(path, method: 'POST'), (_) {
      _responding = false;
    }, refresh: true);
  }

  void _stopStream() {
    _streamTimer?.cancel();
    _streamTimer = null;
    _generation++;
  }

  // --- Approvals ------------------------------------------------------------

  /// Answers a pending tool approval. The real client posts this to the backend
  /// and the run continues; here the card resolves in place.
  Future<void> resolveApproval(
    ApprovalBlock approval, {
    required bool approved,
    String? reason,
  }) async {
    if (remote != null && approval.id != null) {
      await _resolveLiveApproval(approval.id!, approved, reason);
      return;
    }
    final ToolState state = approved ? ToolState.done : ToolState.error;
    final String label = approved
        ? 'approved · ${approval.toolName}'
        : 'declined · ${approval.toolName}';
    _thread = <ChatMessage>[
      for (final ChatMessage message in _thread)
        message.copyWith(
          blocks: <ChatBlock>[
            for (final ChatBlock block in message.blocks)
              if (identical(block, approval))
                ToolBlock(
                  label: label,
                  detail: approved
                      ? 'Saved notes/reply.md'
                      : reason ?? approval.reason,
                  state: state,
                )
              else
                block,
          ],
        ),
    ];
    _emit();
  }

  Future<void> _resolveLiveApproval(
    String id,
    bool approved,
    String? reason,
  ) async {
    if (api == null) return;
    final path =
        '/approvals/${encoded(id)}?workspaceId=${encoded(workspace.id)}';
    await _mutation(
      () => api!.request(
        path,
        method: 'POST',
        body: {
          'approved': approved,
          if (!approved && reason != null) 'reason': reason.trim(),
        },
      ),
      (value) => remote!.approvals = object(value),
      refresh: true,
    );
  }

  Future<void> retryLoad() async {
    if (remote != null) {
      await refreshLive();
    } else {
      await openBot(bot.id);
    }
  }

  // --- Workspace level ------------------------------------------------------

  /// Fills the home screen's lists. Called once after sign-in and again on
  /// pull-to-refresh; failures land in [error] so home can show a retry.
  Future<void> loadRecents({int limit = 6}) async {
    // Separate counter: a pull-to-refresh must never cancel a reply that is
    // mid-stream, which would leave the composer stuck in "stop" state.
    final int generation = ++_workspaceGeneration;
    _error = null;
    try {
      await _repository.refresh();
      if (generation != _workspaceGeneration) return;
      _recents = _repository.recentConversations(limit: limit);
    } on MukaiDataException catch (failure) {
      if (generation != _workspaceGeneration) return;
      _error = failure.message;
    } catch (failure) {
      if (generation != _workspaceGeneration) return;
      _error = 'The workspace could not be reached. $_describe(failure)';
    } finally {
      _emit();
    }
  }
}
