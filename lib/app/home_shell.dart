/// A single workspace canvas with a gesture-driven conversation sidebar.
library;

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'sidebar_canvas.dart';

import '../design/appearance.dart';
import '../design/widgets.dart';
import '../domain/models.dart';
import '../features/chat/chat_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/search/workspace_search.dart';
import '../features/connected/connected_features_screen.dart';
import '../features/connected/connected_settings_screen.dart';
import 'scope.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.onDisconnect});
  final VoidCallback? onDisconnect;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _canvas = GlobalKey<SidebarCanvasState>();
  int _index = 0;
  MukaiBot? _bot;
  String? _conversationId;
  bool _fresh = false;
  int _chatKey = 0;
  String _kind = 'private';
  String? _chatTitle;
  List<String> _memberBotIds = [];

  void _openSidebar() {
    FocusManager.instance.primaryFocus?.unfocus();
    _canvas.currentState?.open();
  }

  void _destination(int index) {
    MukaiScope.sessionOf(context).showWorkspace();
    _canvas.currentState?.close();
    setState(() {
      _index = index;
      _bot = null;
    });
  }

  void _openBot(
    MukaiBot bot, {
    String? conversationId,
    bool fresh = false,
    String kind = 'private',
    String? title,
  }) {
    _canvas.currentState?.close();
    setState(() {
      _bot = bot;
      _kind = kind;
      _chatTitle = title;
      _conversationId = conversationId;
      _fresh = fresh;
      _chatKey++;
    });
  }

  void _openConversation(Conversation conversation) {
    final session = MukaiScope.sessionOf(context);
    final bot = conversation.kind == 'space' && conversation.botIds.isEmpty
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

  Future<void> _switchWorkspace() async {
    final session = MukaiScope.sessionOf(context);
    await showMukaiSheet<void>(
      context: context,
      builder: (context) => SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetGrabber(label: 'Your workspaces'),
              for (final workspace in session.workspaces)
                MukaiRow(
                  title: workspace.name,
                  subtitle: workspace.kind,
                  selected: workspace.id == session.workspace.id,
                  onTap: () async {
                    Navigator.pop(context);
                    _canvas.currentState?.close();
                    await session.selectWorkspace(workspace.id);
                    if (mounted) {
                      setState(() {
                        _bot = null;
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
      await openPursuit(context, result.id, _openConversation);
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
    listenable: MukaiScope.sessionOf(context),
    builder: (context, _) => _buildShell(context),
  );

  Widget _buildShell(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    final Widget body;
    if (_bot != null) {
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
                  MukaiIconButton(
                    icon: Icons.view_sidebar_outlined,
                    tooltip: 'Open sidebar',
                    border: false,
                    onTap: _openSidebar,
                  ),
                  const Spacer(),
                  const MukaiWordmark(size: 25),
                  const Spacer(),
                  MukaiIconButton(
                    icon: Icons.edit_square,
                    tooltip: 'New chat',
                    border: false,
                    onTap: _newChat,
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
                          ))
                  : IndexedStack(
                      index: _index,
                      children: <Widget>[
                        HomeScreen(
                          onOpenBot: (bot) => _openBot(bot),
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
    final colors = MukaiColors.of(context);
    final session = MukaiScope.sessionOf(context);
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
                          (0, 'Workspace', Icons.grid_view_rounded),
                          (1, 'Pursuits', Icons.track_changes_rounded),
                          (2, 'Spaces', Icons.layers_outlined),
                          if (session.updateCount > 0)
                            (5, 'Updates', Icons.notifications_none_rounded),
                          (3, 'Tools', Icons.extension_outlined),
                        ])
                      _SidebarItem(
                        label: label,
                        badge: index == 5
                            ? (session.unreadUpdateCount > 0
                                  ? session.unreadUpdateCount
                                  : session.updateCount)
                            : null,
                        icon: icon,
                        selected: _bot == null && _index == index,
                        onTap: () => _destination(index),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 25, 14, 10),
                      child: _SidebarHeading('Companions'),
                    ),
                    for (final bot in session.bots)
                      _SidebarItem(
                        label: bot.name,
                        leading: GhostAvatar(
                          mascot: bot.mascot,
                          identity: bot.identity,
                          size: 27,
                        ),
                        selected: _bot?.id == bot.id,
                        onTap: () => _openBot(bot),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 25, 14, 10),
                      child: _SidebarHeading('Recent conversations'),
                    ),
                    if (session.recents.isEmpty)
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
                    for (final conversation in session.recents)
                      _SidebarItem(
                        label: conversation.title,
                        leading: _ConversationAvatar(
                          conversation: conversation,
                          bots: session.bots,
                        ),
                        onTap: () => _openConversation(conversation),
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
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.selected = false,
    this.badge,
  });
  final int? badge;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: ListTile(
          minTileHeight: 46,
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          leading:
              leading ??
              Icon(
                icon,
                size: 20,
                color: selected ? colors.accentInk : colors.textSecondary,
              ),
          trailing: badge == null
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
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: colors.accentInk),
                    ),
                  ),
                ),
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
