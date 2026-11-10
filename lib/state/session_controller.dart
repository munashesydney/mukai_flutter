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
import 'pursuit_sidebar_state.dart';
import '../core/message_reference.dart';

class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController(this._repository) {
    if (remote != null) {
      WidgetsBinding.instance.addObserver(this);
      _startPolling();
      unawaited(refreshNotices());
      pursuitSidebar = PursuitSidebarState(api!);
      unawaited(pursuitSidebar!.refresh(workspace.id));
    }
  }

  ApiRepository? get remote =>
      _repository is ApiRepository ? _repository : null;
  MukaiApiClient? get api => remote?.api;
  PursuitSidebarState? pursuitSidebar;
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
    // Detaching the phone's stream does not stop the server's response.
    if (remote != null && _respondingInConversation) {
      _backgroundWorking[(workspace.id, _conversationId ?? 'bot-${bot.id}')] =
          bot.id;
    }
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
  final Map<String, MessageReference> references = {};
  MessageReference? get reference => references[draftKey];
  void setReference(MessageReference? value, {String? conversationId}) {
    final key = conversationId ?? draftKey;
    if (value == null) {
      references.remove(key);
    } else {
      references[key] = value;
    }
    _emit();
  }

  ChatMessage? get activeReply =>
      _thread.where((m) => !m.fromUser && m.streaming).lastOrNull;
  final Set<String> pendingFollowupActions = {};
  final Map<String, ({String text, String id, bool queued})>
  _uncertainRequests = {};
  final Set<String> _queueSubmitting = {};
  bool get submittingFollowup => _queueSubmitting.contains(draftKey);
  void _reconcileDraft(String key, List<ChatMessage> messages) {
    final pending = _uncertainRequests[key];
    if (pending != null &&
        (messages.any((m) => m.requestId == pending.id && m.fromUser) ||
            followups.any((item) => item['id'] == pending.id) ||
            messages
                .expand((m) => m.blocks)
                .whereType<SteeringBlock>()
                .any((b) => b.id == pending.id))) {
      _uncertainRequests.remove(key);
      final submitted = splitMessageReference(pending.text);
      if (drafts[key] == submitted.text) drafts.remove(key);
      if (references[key]?.format(submitted.text) == pending.text) {
        references.remove(key);
      }
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
    // Refresh background chat flags even while a different chat stays open.
    if (values[1] is Map &&
        _chatVisible &&
        _bot != null &&
        workingConversationIds.isNotEmpty) {
      unawaited(loadRecents());
    }
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
      if (_chatVisible && _bot != null) {
        await remote!.refreshWorkspaceSettings();
      }
      if (!_isCurrent(generation)) return;
      if (!_chatVisible) {
        await remote!.refresh();
        if (_isCurrent(generation)) {
          _reconcileBackgroundWorking();
          _recents = remote!.recentConversations();
          _emit();
        }
        return;
      }
      if (_bot == null) {
        await remote!.refresh();
        if (_isCurrent(generation)) {
          _reconcileBackgroundWorking();
          _recents = remote!.recentConversations();
        }
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
          followups = pending;
          _reconcileDraft(draftKey, thread);
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

  Future<void> setWorkspaceTimeZone(String workspaceId, String timeZone) async {
    if (remote == null) {
      throw const ApiException('Connect to your Mukai to change its timezone.');
    }
    await remote!.saveWorkspaceTimeZone(workspaceId, timeZone);
    if (!_disposed) _emit();
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
    unawaited(pursuitSidebar?.refresh(id));
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

  Future<bool> updateFollowup(String id, String action, {String? text}) async {
    if (api == null || !pendingFollowupActions.add(id)) return false;
    final active = activeReply;
    if (action == 'steer' && active == null) {
      pendingFollowupActions.remove(id);
      _error = 'Wait for the bot to start responding before steering.';
      _emit();
      return false;
    }
    final path = '${remote!.root(bot.id, _conversationId)}/followups';
    _error = null;
    _emit();
    try {
      await _mutation(
        () => api!.request(
          path,
          method: 'PUT',
          body: {
            'id': id,
            'action': action,
            'text': ?text,
            if (action == 'steer') 'expectedRequestId': active!.requestId,
          },
        ),
        (value) => followups = objects(value),
      );
      return _error == null;
    } finally {
      pendingFollowupActions.remove(id);
      _emit();
    }
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
  final Map<(String, String), DateTime> _conversationInteractions = {};
  final Map<(String, String), String> _backgroundWorking = {};
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

  /// All available private/bot chats for paginated bot groups.
  List<Conversation> get botConversations =>
      _repository.recentConversations(limit: null);

  bool get hasMoreSidebarConversations => remote?.hasMoreConversations ?? false;
  bool get loadingSidebarConversations =>
      remote?.loadingMoreConversations ?? false;

  Future<void> loadMoreSidebarConversations() async {
    final repository = remote;
    if (repository == null || repository.loadingMoreConversations) return;
    final pending = repository.loadMoreConversations();
    _emit();
    try {
      await pending;
    } finally {
      _emit();
    }
  }

  /// Sidebar history includes older chats and honors local interactions as well
  /// as the server's latest activity, scoped to the current workspace.
  List<Conversation> get sidebarConversations {
    final conversations = botConversations;
    for (final conversation in remote?.allConversations ?? <Conversation>[]) {
      if (_conversationInteractions.containsKey((
            workspace.id,
            conversation.id,
          )) &&
          !conversations.any((chat) => chat.id == conversation.id)) {
        conversations.add(conversation);
      }
    }
    DateTime lastInteraction(Conversation chat) {
      final opened = _conversationInteractions[(workspace.id, chat.id)];
      return opened != null && opened.isAfter(chat.updatedAt)
          ? opened
          : chat.updatedAt;
    }

    conversations.sort((a, b) {
      final order = lastInteraction(b).compareTo(lastInteraction(a));
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return conversations;
  }

  void _touchConversation() {
    final id = _conversationId;
    if (id != null) {
      _conversationInteractions[(workspace.id, id)] = DateTime.now();
    }
  }

  Iterable<Map<String, dynamic>> get _conversationWork sync* {
    for (final state in ['running', 'queued']) {
      for (final work in objects(aiActivity[state])) {
        final workWorkspace = work['workspaceId'];
        final kind = work['kind'];
        if ((kind == null || kind == 'chat') &&
            (workWorkspace == null || workWorkspace == workspace.id)) {
          yield work;
        }
      }
    }
  }

  bool get hasRunningPursuit => objects(
    aiActivity['pursuitRunning'],
  ).any((run) => run['workspaceId'] == workspace.id);

  bool get _respondingInConversation => !readOnly && _bot != null && responding;

  /// The picker includes running work in every workspace, not just this one.
  Set<String> get workingWorkspaceIds => {
    for (final id
        in (aiActivity['workingWorkspaceIds'] as List? ?? const [])
            .whereType<String>())
      if (id.isNotEmpty) id,
    for (final state in ['running', 'pursuitRunning'])
      for (final work in objects(aiActivity[state]))
        if (string(work['workspaceId']).isNotEmpty) string(work['workspaceId']),
    if ((_bot != null && responding) ||
        botConversations.any((chat) => chat.isWorking) ||
        _backgroundWorking.keys.any((key) => key.$1 == workspace.id))
      workspace.id,
  };

  Set<String> get workingConversationIds => {
    for (final chat in botConversations)
      if (chat.isWorking) chat.id,
    for (final work in _conversationWork)
      if (string(work['conversationId']).isNotEmpty)
        string(work['conversationId']),
    for (final entry in _backgroundWorking.keys)
      if (entry.$1 == workspace.id) entry.$2,
    if (_respondingInConversation) _conversationId ?? 'bot-${bot.id}',
  };

  Set<String> get workingBotIds {
    final working = workingConversationIds;
    return {
      for (final chat in botConversations)
        if (working.contains(chat.id))
          if (chat.kind == 'bot' && chat.botIds.length > 1)
            chat.botIds[1]
          else
            chat.botId,
      for (final work in _conversationWork)
        if (string(work['botId']).isNotEmpty) string(work['botId']),
      for (final entry in _backgroundWorking.entries)
        if (entry.key.$1 == workspace.id) entry.value,
      if (_respondingInConversation) bot.id,
    };
  }

  void _reconcileBackgroundWorking() {
    _backgroundWorking.removeWhere((key, _) => key.$1 == workspace.id);
  }

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
      pursuitSidebar?.dispose();
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
    if (sameBot && _space == space && readOnly == viewOnly) {
      _touchConversation();
      _emit();
      if (remote != null) unawaited(refreshLive());
      return;
    }
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
    _touchConversation();
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
        _touchConversation();
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

  /// Sends a reply or queues a follow-up while the connected bot is working.
  Future<void> send(String rawText, {bool queue = false}) async {
    final String text = rawText.trim();
    if (_loading || (text.isEmpty && attachments.isEmpty) || readOnly) return;
    _touchConversation();
    if (remote != null) {
      await _sendLive(text, queue: queue);
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

  Future<void> _sendLive(
    String text, {
    String? retryMessageId,
    bool queue = false,
  }) async {
    if (_bot == null) return;
    final key = draftKey;
    final selected = reference;
    final sentText = selected?.format(text) ?? text;
    if (queue ||
        responding ||
        (_uncertainRequests[key]?.queued == true &&
            _uncertainRequests[key]?.text == sentText)) {
      if (!_queueSubmitting.add(key)) return;
      _error = null;
      _emit();
      final pending = _uncertainRequests[key];
      final requestId = pending?.text == sentText
          ? pending!.id
          : newRequestId();
      _uncertainRequests[key] = (text: sentText, id: requestId, queued: true);
      final ids = attachments.map((a) => string(a['id'])).toList();
      final path = '${remote!.root(bot.id, _conversationId)}/followups';
      final body = {
        'id': requestId,
        'text': sentText,
        'attachmentIds': ids,
        if (_space) 'botId': bot.id.isEmpty ? null : bot.id,
      };
      try {
        await _mutation(() => api!.request(path, method: 'POST', body: body), (
          value,
        ) {
          followups = objects(value);
          if (_uncertainRequests[key]?.id == requestId) {
            _uncertainRequests.remove(key);
          }
          if (references[key] == selected) references.remove(key);
          attachments.removeWhere((a) => ids.contains(a['id']));
          if (drafts[key] == text || drafts[key]?.isEmpty == true) {
            drafts.remove(key);
          }
        });
        if (_error != null &&
            draftKey == key &&
            (drafts[key]?.isEmpty ?? true)) {
          drafts[key] = text;
          _emit();
        }
      } finally {
        _queueSubmitting.remove(key);
        _emit();
      }
      return;
    }
    _error = null;
    _responding = true;
    _emit();
    final generation = ++_generation;
    final sentAttachments = attachments.map((a) => string(a['id'])).toList();
    final pending = _uncertainRequests[key];
    final requestId = pending?.text == sentText ? pending!.id : newRequestId();
    _uncertainRequests[key] = (text: sentText, id: requestId, queued: false);
    bool accepted = false;
    final complete = Completer<void>();
    _sendCompletion = complete;
    _liveSubscription = remote!
        .streamReply(
          botId: bot.id,
          text: sentText,
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
            if (remote!.followupUpdates.containsKey(key)) {
              followups = remote!.followupUpdates[key]!;
            }
            accepted =
                accepted ||
                thread.any((m) => m.requestId == requestId && m.fromUser);
            if (accepted) {
              _uncertainRequests.remove(key);
              if (references[key] == selected) references.remove(key);
            }
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
      unawaited(pursuitSidebar?.refresh(workspace.id));
      _reconcileBackgroundWorking();
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
