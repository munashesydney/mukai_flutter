/// A single workspace canvas with a gesture-driven conversation sidebar.
library;

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'sidebar_canvas.dart';

import '../design/appearance.dart';
import '../core/push_notifications.dart';
import '../design/glass.dart';
import '../design/widgets.dart';
import '../domain/models.dart';
import '../features/chat/chat_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/search/workspace_search.dart';
import '../features/connected/connected_features_screen.dart';
import '../features/connected/connected_settings_screen.dart';
import '../features/connected/pursuit_sidebar.dart';
import '../features/connected/connected_widgets.dart' show connectionNotice;
import 'scope.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.onDisconnect, this.pushTarget});
  final PushTarget? pushTarget;
  final VoidCallback? onDisconnect;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _canvas = GlobalKey<SidebarCanvasState>();
  final _sidebarScroll = ScrollController(keepScrollOffset: false);
  int _index = 0;
  MukaiBot? _bot;
  String? _conversationId;
  bool _fresh = false;
  int _chatKey = 0;
  String _kind = 'private';
  String? _chatTitle;
  List<String> _memberBotIds = [];
  ({String pursuitId, String runId})? _run;
  String? _closingRunId;
  final Set<String> _joinedRuns = {};
  int _chatNavigation = 0;
  String? _historyWorkspace;
  int _historyLimit = 12;

  @override
  void initState() {
    super.initState();
    if (widget.pushTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPushTarget(widget.pushTarget!);
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pushTarget != null &&
        widget.pushTarget != oldWidget.pushTarget) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPushTarget(widget.pushTarget!);
      });
    }
  }

  int _pushNavigation = 0;
  Future<void> _openPushTarget(PushTarget target) async {
    final navigation = ++_pushNavigation;
    final session = MukaiScope.sessionOf(context);
    try {
      await session.loadRecents();
      if (!mounted || navigation != _pushNavigation) return;
      if (!session.workspaces.any((item) => item.id == target.workspaceId)) {
        return;
      }
      if (session.workspace.id != target.workspaceId) {
        await session.selectWorkspace(target.workspaceId);
      }
      await session.loadRecents();
      if (!mounted || session.workspace.id != target.workspaceId) return;
      var conversation = session.remote?.allConversations
          .where((item) => item.id == target.conversationId)
          .firstOrNull;
      if (conversation == null &&
          session.api != null &&
          session.remote != null) {
        conversation = await session.remote!.getConversation(
          target.conversationId,
        );
      }
      if (mounted &&
          navigation == _pushNavigation &&
          session.workspace.id == target.workspaceId &&
          conversation != null) {
        _openConversation(conversation);
      }
    } catch (_) {
      /* A deleted/offline conversation remains in the user's notification history. */
    }
  }

  void _openSidebar() {
    FocusManager.instance.primaryFocus?.unfocus();
    _canvas.currentState?.open();
    // Include new chats and changes made elsewhere when navigation opens.
    final session = MukaiScope.sessionOf(context);
    if (session.api != null) {
      session.loadRecents();
      session.pursuitSidebar?.refresh(session.workspace.id, force: true);
    }
  }

  @override
  void dispose() {
    _sidebarScroll.dispose();
    super.dispose();
  }

  void _destination(int index) {
    _chatNavigation++;
    MukaiScope.sessionOf(context).showWorkspace();
    _canvas.currentState?.close();
    setState(() {
      _index = index;
      _bot = null;
      _run = null;
      _closingRunId = null;
    });
  }

  void _openBot(
    MukaiBot bot, {
    String? conversationId,
    bool fresh = false,
    String kind = 'private',
    String? title,
  }) {
    _chatNavigation++;
    _canvas.currentState?.close();
    setState(() {
      _bot = bot;
      _run = null;
      _closingRunId = null;
      _kind = kind;
      _chatTitle = title;
      _conversationId = conversationId;
      _fresh = fresh;
      _chatKey++;
    });
  }

  void _openConversation(Conversation conversation) {
    if (conversation.kind == 'pursuit_run' &&
        conversation.pursuitId != null &&
        conversation.runId != null) {
      _openPursuitRun(conversation.pursuitId!, conversation.runId!);
      return;
    }
    final session = MukaiScope.sessionOf(context);
    final bot = conversation.kind == 'bot' && conversation.botIds.length == 2
        ? session.remote!.botById(conversation.botIds[1])
        : conversation.kind == 'space' && conversation.botIds.isEmpty
        ? session.remote!.botById('')
        : session.bots.where((b) => b.id == conversation.botId).firstOrNull ??
              session.bots
                  .where((b) => conversation.botIds.contains(b.id))
                  .firstOrNull ??
              session.bot;
    _memberBotIds = conversation.botIds;
    _openBot(
      bot,
      conversationId: conversation.id,
      kind: conversation.kind,
      title: conversation.title,
    );
  }

  void _openPursuitRun(String pursuitId, String runId) {
    _chatNavigation++;
    final session = MukaiScope.sessionOf(context);
    session.showWorkspace();
    session.pursuitSidebar?.ensureRuns(pursuitId);
    _canvas.currentState?.close();
    setState(() {
      _index = 1;
      _bot = null;
      _run = (pursuitId: pursuitId, runId: runId);
      _closingRunId = null;
    });
  }

  Future<void> _openNotificationSource(NotificationSource source) async {
    if (source.isRun) {
      _openPursuitRun(source.pursuitId!, source.runId!);
      return;
    }
    final navigation = ++_chatNavigation;
    try {
      final repository = MukaiScope.sessionOf(context).remote!;
      final conversation = await repository.getConversation(
        source.conversationId,
      );
      if (mounted && navigation == _chatNavigation) {
        _openConversation(conversation);
      }
    } catch (error) {
      if (mounted && navigation == _chatNavigation) {
        connectionNotice(context, error);
      }
    }
  }

  Future<void> _switchWorkspace() async {
    final session = MukaiScope.sessionOf(context);
    session.refreshNotices();
    await showMukaiSheet<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) => SingleChildScrollView(
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetGrabber(label: 'Your workspaces'),
                for (final workspace in session.workspaces)
                  MukaiRow(
                    key: ValueKey('workspace-picker-${workspace.id}'),
                    title: workspace.name,
                    subtitle: workspace.kind,
                    selected: workspace.id == session.workspace.id,
                    trailing: session.workingWorkspaceIds.contains(workspace.id)
                        ? const BouncingDots()
                        : null,
                    onTap: () async {
                      _chatNavigation++;
                      Navigator.pop(context);
                      _canvas.currentState?.close();
                      await session.selectWorkspace(workspace.id);
                      if (mounted) {
                        setState(() {
                          _bot = null;
                          _run = null;
                          _index = 0;
                        });
                      }
                    },
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _search() async {
    final result = await Navigator.of(context).push<WorkspaceSearchResult>(
      MaterialPageRoute(
        builder: (_) => const WorkspaceSearchPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || result == null) return;
    _canvas.currentState?.close();
    if (result.kind == WorkspaceSearchKind.companion) {
      _openBot(result.bot!);
    } else if (result.conversation != null) {
      _openConversation(result.conversation!);
    } else {
      _destination(1);
      await openPursuit(context, result.id, _openPursuitRun);
    }
  }

  void _newChat() {
    final bots = MukaiScope.sessionOf(context).bots;
    showMukaiSheet<void>(
      context: context,
      builder: (BuildContext context) => SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SheetGrabber(label: 'Who’s on your mind?'),
              if (bots.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Add a companion in your workspace to start a conversation.',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Pick a companion and start something new.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              for (final bot in bots)
                MukaiRow(
                  title: bot.name,
                  subtitle: bot.role,
                  leading: GhostAvatar(
                    mascot: bot.mascot,
                    identity: bot.identity,
                  ),
                  onTap: () async {
                    final sheet = ModalRoute.of(context);
                    Navigator.pop(context);
                    await sheet?.completed;
                    if (mounted) _openBot(bot, fresh: true);
                  },
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      MukaiScope.sessionOf(context),
      MukaiScope.appearanceOf(context),
    ]),
    builder: (context, _) => _buildShell(context),
  );

  Widget _buildShell(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    final run = _run;
    MukaiScope.pushOf(
      context,
    )?.visible(_bot == null && run == null ? null : session.conversationId);
    final Widget body;
    if (run != null) {
      body = TweenAnimationBuilder<double>(
        key: ValueKey('run-entrance-${run.runId}'),
        tween: Tween(
          begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0,
          end: _closingRunId == run.runId ? 0 : 1,
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 340),
        curve: _closingRunId == run.runId
            ? Curves.easeInCubic
            : Curves.easeOutCubic,
        onEnd: () {
          if (_closingRunId != run.runId || _run != run) return;
          _destination(1);
          openPursuit(context, run.pursuitId, _openPursuitRun, animate: false);
        },
        builder: (context, value, child) => FractionalTranslation(
          translation: Offset(0, 1 - value),
          child: child,
        ),
        child: PursuitRunChat(
          key: ValueKey(run.runId),
          pursuitId: run.pursuitId,
          runId: run.runId,
          joined: _joinedRuns.contains(run.runId),
          onJoin: () => setState(() => _joinedRuns.add(run.runId)),
          onMenu: _openSidebar,
          onHistory: () {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _closingRunId = run.runId);
          },
          onOpenSource: _openNotificationSource,
        ),
      );
    } else if (_bot != null) {
      body = ChatScreen(
        key: ValueKey<int>(_chatKey),
        bot: _bot!,
        conversationId: _conversationId,
        fresh: _fresh,
        memberBotIds: _memberBotIds,
        kind: _kind,
        title: _chatTitle,
        onMenu: _openSidebar,
        onNewChat: _newChat,
        onOpenSource: _openNotificationSource,
      );
    } else {
      body = SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: <Widget>[
                  MukaiGlassPill(
                    child: MukaiIconButton(
                      icon: Icons.view_sidebar_outlined,
                      tooltip: 'Open sidebar',
                      border: false,
                      onTap: _openSidebar,
                    ),
                  ),
                  const Spacer(),
                  const MukaiWordmark(size: 25),
                  const Spacer(),
                  MukaiGlassPill(
                    child: MukaiIconButton(
                      icon: Icons.edit_square,
                      tooltip: 'New chat',
                      border: false,
                      onTap: _newChat,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: session.api != null && _index > 0
                  ? (_index == 5
                        ? UpdatesScreen(
                            key: ValueKey(session.workspace.id),
                            onOpenConversation: _openConversation,
                          )
                        : _index == 4
                        ? ConnectedSettingsScreen(
                            key: ValueKey(session.workspace.id),
                            onDisconnect: widget.onDisconnect ?? () {},
                          )
                        : ConnectedFeaturesScreen(
                            key: ValueKey('${session.workspace.id}/$_index'),
                            kind: const [
                              'workspace',
                              'pursuits',
                              'spaces',
                              'tools',
                            ][_index],
                            onOpenConversation: _openConversation,
                            onOpenRun: _openPursuitRun,
                          ))
                  : IndexedStack(
                      index: _index,
                      children: <Widget>[
                        HomeScreen(
                          onOpenBot: (bot) => _openBot(bot),
                          onNewConversation: (bot) =>
                              _openBot(bot, fresh: true),
                          onOpenConversation: _openConversation,
                          onSwitchWorkspace: _switchWorkspace,
                          onOpenSettings: () => _destination(4),
                        ),
                        if (session.api != null)
                          const SizedBox.shrink()
                        else
                          _EmptyDestination(
                            title: 'Pursuits',
                            headline: 'Big things start small.',
                            body:
                                'Give a bot a goal to keep working toward. Your pursuits will have a home here.',
                            icon: Icons.track_changes_rounded,
                            onChat: _newChat,
                          ),
                        if (session.api != null)
                          const SizedBox.shrink()
                        else
                          _EmptyDestination(
                            title: 'Spaces',
                            headline: 'Room for your next idea.',
                            body:
                                'Files, notes, and the things you make together. Spaces from your workspace will appear here.',
                            icon: Icons.layers_outlined,
                            onChat: _newChat,
                          ),
                        if (session.api != null)
                          const SizedBox.shrink()
                        else
                          _EmptyDestination(
                            title: 'Tools',
                            headline: 'A little more possibility.',
                            body:
                                'Connect tools in your desktop workspace to give your companions new ways to help.',
                            icon: Icons.auto_awesome_outlined,
                            onChat: _newChat,
                          ),
                        if (session.api != null)
                          const SizedBox.shrink()
                        else
                          const SettingsScreen(),
                        _EmptyDestination(
                          title: 'Updates',
                          headline: 'You’re all caught up.',
                          body: 'News from your companions will appear here.',
                          icon: Icons.notifications_none_rounded,
                          onChat: _newChat,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    }
    return SidebarCanvas(key: _canvas, sidebar: _sidebar(context), child: body);
  }

  Widget _sidebar(BuildContext context) {
    final minimalism = MukaiScope.appearanceOf(context).preferences.minimalism;
    final colors = MukaiColors.of(context);
    final session = MukaiScope.sessionOf(context);
    final conversations = session.sidebarConversations;
    final historyLimit = _historyWorkspace == session.workspace.id
        ? _historyLimit
        : 12;
    final workingConversations = session.workingConversationIds;
    final activeConversationId = _bot == null ? null : session.conversationId;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 10, 14),
            child: Row(
              children: [
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MukaiWordmark(size: 27),
                  ),
                ),
                MukaiIconButton(
                  icon: Icons.search_rounded,
                  tooltip: 'Search workspace',
                  border: false,
                  onTap: _search,
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  key: const PageStorageKey('sidebar-scroll'),
                  controller: _sidebarScroll,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 104),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Tooltip(
                        message: 'Switch workspace',
                        child: PressableScale(
                          onTap: _switchWorkspace,
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    session.workspace.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: colors.textSecondary),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: colors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (final (int index, String label, IconData icon)
                        in <(int, String, IconData)>[
                          (
                            0,
                            minimalism ? 'Bots' : 'Workspace',
                            Icons.grid_view_rounded,
                          ),
                          (1, 'Pursuits', Icons.track_changes_rounded),
                          (2, 'Spaces', Icons.layers_outlined),
                          if (session.updateCount > 0)
                            (5, 'Updates', Icons.notifications_none_rounded),
                          (3, 'Tools', Icons.extension_outlined),
                        ]) ...[
                      _SidebarItem(
                        label: label,
                        badge: index == 5
                            ? (session.unreadUpdateCount > 0
                                  ? session.unreadUpdateCount
                                  : session.updateCount)
                            : null,
                        icon: icon,
                        activityLabel: index == 1 && session.hasRunningPursuit
                            ? 'Pursuit running'
                            : null,
                        leading: index == 0 && minimalism
                            ? const GhostAvatar(
                                mascot: Mascot.logo,
                                identity: BotIdentity.mukai,
                                size: 20,
                              )
                            : null,
                        selected:
                            _bot == null && _run == null && _index == index,
                        onTap: () => _destination(index),
                      ),
                      if (index == 1 && _index == 1 && session.api != null)
                        PursuitSidebar(
                          key: ValueKey(session.workspace.id),
                          selectedPursuitId: _run?.pursuitId,
                          selectedRunId: _run?.runId,
                          onOpenRun: _openPursuitRun,
                          state: session.pursuitSidebar!,
                        ),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 25, 14, 10),
                      child: _SidebarHeading('Conversations'),
                    ),
                    if (conversations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          'Your next idea starts here.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    for (final (index, conversation) in conversations.indexed)
                      if (index < historyLimit ||
                          conversation.id == activeConversationId)
                        _SidebarItem(
                          key: ValueKey(
                            'sidebar-conversation-${conversation.id}',
                          ),
                          label: conversation.title,
                          selected: activeConversationId == conversation.id,
                          trailing:
                              workingConversations.contains(conversation.id)
                              ? const BouncingDots()
                              : null,
                          leading: _ConversationAvatar(
                            conversation: conversation,
                            bots: session.bots,
                          ),
                          onTap: () => _openConversation(conversation),
                        ),
                    if (conversations.length > historyLimit)
                      TextButton(
                        onPressed: () => setState(() {
                          _historyWorkspace = session.workspace.id;
                          _historyLimit = historyLimit + 12;
                        }),
                        child: const Text('Load more conversations'),
                      ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 30, 12, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.cardMuted.withValues(alpha: 0),
                          colors.cardMuted,
                          colors.cardMuted,
                        ],
                        stops: const [0, .45, 1],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Semantics(
                              button: true,
                              label: 'New chat',
                              child: PressableScale(
                                onTap: () {
                                  _canvas.currentState?.close();
                                  _newChat();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.accentColor,
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.accentColor.withValues(
                                          alpha: .2,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_square,
                                        size: 20,
                                        color: colors.textOnAccent,
                                      ),
                                      const SizedBox(width: 9),
                                      Flexible(
                                        child: Text(
                                          'New chat',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color: colors.textOnAccent,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.card.withValues(alpha: .9),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.hairlineStrong,
                                ),
                              ),
                              child: MukaiIconButton(
                                icon: Icons.settings_outlined,
                                tooltip: 'Settings',
                                border: false,
                                size: 50,
                                onTap: () => _destination(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeading extends StatelessWidget {
  const _SidebarHeading(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: MukaiColors.of(context).textMuted,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.conversation, required this.bots});
  final Conversation conversation;
  final List<MukaiBot> bots;

  @override
  Widget build(BuildContext context) {
    final bot = bots.where((bot) => bot.id == conversation.botId).firstOrNull;
    return GhostAvatar(
      mascot: bot?.mascot ?? Mascot.defaultBot,
      identity: bot?.identity ?? BotIdentity.mukai,
      size: 27,
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.activityLabel,
    this.leading,
    this.trailing,
    this.selected = false,
    this.badge,
  });
  final int? badge;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? activityLabel;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final iconColor = selected ? colors.accentInk : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: ListTile(
          selected: selected,
          minTileHeight: 46,
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          leading:
              leading ??
              (activityLabel == null
                  ? Icon(icon, size: 20, color: iconColor)
                  : SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        color: iconColor,
                        strokeWidth: 2,
                        value: MediaQuery.disableAnimationsOf(context)
                            ? .75
                            : null,
                        semanticsLabel: activityLabel,
                        semanticsValue: '',
                      ),
                    )),
          trailing:
              trailing ??
              (badge == null
                  ? null
                  : Semantics(
                      label: '$badge ${badge == 1 ? 'update' : 'updates'}',
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$badge',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.accentInk),
                        ),
                      ),
                    )),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: selected ? colors.accentInk : colors.ink,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          onTap: () {
            Haptics.select();
            onTap();
          },
        ),
      ),
    );
  }
}

class _EmptyDestination extends StatelessWidget {
  const _EmptyDestination({
    required this.title,
    required this.headline,
    required this.body,
    required this.icon,
    required this.onChat,
  });
  final String title, headline, body;
  final IconData icon;
  final VoidCallback onChat;
  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: colors.accentSoft,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Icon(icon, size: 30, color: colors.accentInk),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    headline,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  MukaiButton(
                    label: 'Start a conversation',
                    variant: MukaiButtonVariant.tonal,
                    onPressed: onChat,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
