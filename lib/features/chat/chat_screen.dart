/// Conversation screen: header, thread, composer, and the activity sheet.
///
/// The list is built bottom-up (`reverse: true`) so a streamed reply keeps the
/// reader pinned at the newest block — the behaviour that matters most in a
/// chat that answers slowly.
library;

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../app/scope.dart';
import '../../design/appearance.dart';
import '../../design/theme.dart';
import '../../design/widgets.dart';
import '../../domain/models.dart';
import 'widgets/activity_sheet.dart';
import 'widgets/approval_dock.dart';
import 'widgets/ai_queue_notice.dart';
import 'widgets/composer.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.bot,
    this.conversationId,
    this.fresh = false,
    this.onMenu,
    this.onNewChat,
    this.kind = 'private',
    this.title,
    this.memberBotIds = const [],
  });

  final MukaiBot bot;
  final String kind;
  final String? title;
  final List<String> memberBotIds;
  final String? conversationId;
  final bool fresh;
  final VoidCallback? onMenu;
  final VoidCallback? onNewChat;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MukaiScope.sessionOf(context).openBot(
          widget.bot.id,
          conversationId: widget.conversationId,
          fresh: widget.fresh,
          space: widget.kind == 'space',
          viewOnly: widget.kind == 'pursuit_run',
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final bool show = _scroll.hasClients && _scroll.offset > 420;
    if (show == _showJump) return;
    setState(() => _showJump = show);
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: MukaiMotion.normal,
      curve: MukaiMotion.curve,
    );
  }

  Future<void> _attach() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Supported files',
          extensions: [
            'png',
            'jpg',
            'jpeg',
            'webp',
            'pdf',
            'docx',
            'txt',
            'md',
            'csv',
            'json',
            'html',
            'xml',
            'ts',
            'js',
            'py',
            'css',
            'yaml',
            'yml',
            'log',
            'wav',
            'mp3',
            'mp4',
            'mov',
          ],
        ),
      ],
    );
    if (file == null || !mounted) return;
    try {
      await MukaiScope.sessionOf(
        context,
      ).addAttachment(file.name, await file.readAsBytes());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _openActivity() {
    FocusManager.instance.primaryFocus?.unfocus();
    final session = MukaiScope.sessionOf(context);
    return showMukaiSheet<void>(
      context: context,
      builder: (BuildContext _) =>
          ActivitySheet(activity: session.activity, bots: session.bots),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final session = MukaiScope.sessionOf(context);

    return ListenableBuilder(
      listenable: session,
      builder: (BuildContext context, Widget? _) {
        final MukaiBot bot = session.loadingThreads ? widget.bot : session.bot;
        final List<ChatMessage> thread = session.thread
            .where(
              (message) =>
                  message.error != null ||
                  message.blocks.isEmpty ||
                  !message.blocks.every((block) => block is ApprovalBlock),
            )
            .toList()
            .reversed
            .toList();
        final pending = session.pendingApprovals;

        return Scaffold(
          backgroundColor: colors.canvas,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _ChatHeader(
                  bot: bot,
                  title: widget.title,
                  activityCount: session.activity.total,
                  onActivity: _openActivity,
                  onMenu: widget.onMenu,
                  onNewChat: widget.onNewChat,
                ),
                if (session.hasError)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MukaiSpace.screen,
                      MukaiSpace.md,
                      MukaiSpace.screen,
                      0,
                    ),
                    child: MukaiErrorBanner(
                      message: session.error!,
                      onRetry: session.retryLoad,
                    ),
                  ),
                if (session.api != null)
                  AIQueueNotice(
                    activity: session.aiActivity,
                    conversationId: session.conversationId ?? 'bot-${bot.id}',
                  ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (session.loadingThreads)
                        const Center(
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      else if (thread.isEmpty)
                        MukaiEmptyState(
                          title: 'A fresh start with ${bot.name}.',
                          body:
                              'Bring a question, an idea, or something you’d like to move forward.',
                          mascot: bot.mascot,
                          identity: bot.identity,
                        )
                      else
                        Align(
                          alignment: Alignment.topCenter,
                          child: ListView.builder(
                            shrinkWrap: true,
                            controller: _scroll,
                            reverse: true,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(
                              MukaiSpace.screen,
                              MukaiSpace.lg,
                              MukaiSpace.screen,
                              MukaiSpace.md,
                            ),
                            itemCount: thread.length,
                            findChildIndexCallback: (key) {
                              if (key is! ValueKey<String>) return null;
                              final index = thread.indexWhere(
                                (m) => m.id == key.value,
                              );
                              return index < 0 ? null : index;
                            },
                            itemBuilder: (BuildContext context, int index) =>
                                Column(
                                  key: ValueKey(thread[index].id),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    MessageView(
                                      message: thread[index],
                                      bots: session.bots,
                                      onApproval:
                                          (
                                            ApprovalBlock approval,
                                            bool approved,
                                          ) => session.resolveApproval(
                                            approval,
                                            approved: approved,
                                          ),
                                    ),
                                    if (thread[index].error != null)
                                      Text(
                                        thread[index].error!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                      ),
                                    if (session.api != null &&
                                        widget.kind != 'pursuit_run' &&
                                        const [
                                          'failed',
                                          'stopped',
                                          'interrupted',
                                        ].contains(thread[index].status))
                                      TextButton.icon(
                                        onPressed: session.responding
                                            ? null
                                            : () => session.retryMessage(
                                                thread[index],
                                              ),
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Retry response'),
                                      ),
                                    if (session.api != null)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: () => session.saveMessage(
                                            thread[index],
                                          ),
                                          icon: Icon(
                                            thread[index].saved
                                                ? Icons.bookmark
                                                : Icons.bookmark_border,
                                            size: 16,
                                          ),
                                          label: Text(
                                            thread[index].saved
                                                ? 'Saved'
                                                : 'Save',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                          ),
                        ),
                      Positioned(
                        right: MukaiSpace.screen,
                        bottom: MukaiSpace.md,
                        child: IgnorePointer(
                          ignoring: !_showJump,
                          child: AnimatedScale(
                            scale: _showJump ? 1 : 0,
                            duration: MukaiMotion.fast,
                            curve: MukaiMotion.springy,
                            child: _JumpButton(onTap: _jumpToLatest),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (pending.isEmpty &&
                    session.api != null &&
                    session.followups.isNotEmpty)
                  SizedBox(
                    height: 58,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final item in session.followups)
                          Card(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Text(
                                    '${item['state']}: ${item['text']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Send follow-up now',
                                  icon: const Icon(Icons.send_rounded),
                                  onPressed: () => session.updateFollowup(
                                    item['id'] as String,
                                    'send',
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove follow-up',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => session.updateFollowup(
                                    item['id'] as String,
                                    'delete',
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (pending.isEmpty &&
                    widget.kind == 'space' &&
                    session.api != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('Reply with '),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: session.bot.id.isEmpty
                                ? ''
                                : widget.memberBotIds.contains(session.bot.id)
                                ? session.bot.id
                                : '',
                            hint: const Text('Select a companion'),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Post without a bot'),
                              ),
                              for (final bot in session.bots.where(
                                (b) => widget.memberBotIds.contains(b.id),
                              ))
                                DropdownMenuItem(
                                  value: bot.id,
                                  child: Text(bot.name),
                                ),
                            ],
                            onChanged: (id) {
                              if (id != null) session.selectSpaceBot(id);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.kind == 'pursuit_run')
                  const SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Pursuit run · read only'),
                    ),
                  )
                else if (pending.isNotEmpty)
                  SafeArea(top: false, child: ApprovalDock(requests: pending))
                else
                  SafeArea(
                    top: false,
                    bottom: true,
                    child: MukaiComposer(
                      key: ValueKey(session.draftKey),
                      enabled: !session.loadingThreads,
                      autofocus: widget.fresh,
                      botName: widget.kind == 'space'
                          ? (widget.title ?? 'Space')
                          : bot.name,
                      initialDraft: session.drafts[session.draftKey] ?? '',
                      onDraftChanged: (text) =>
                          session.drafts[session.draftKey] = text,
                      allowQueue: session.api != null,
                      onSubmit: session.api != null ? session.send : null,
                      accessMode: session.api == null
                          ? null
                          : session.approvalMode,
                      onModeChanged: session.setApprovalMode,
                      onModelChanged: session.setModel,
                      onAttach: session.api == null || widget.kind == 'space'
                          ? null
                          : _attach,
                      attachments: session.attachments,
                      onRemoveAttachment: session.removeAttachment,
                      responding: session.responding,
                      modelLabel: bot.modelLabel,
                      modelOptions: session.api == null
                          ? const ['Workspace default']
                          : session.modelOptions,
                      onSend: session.send,
                      onStop: session.stop,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.bot,
    required this.activityCount,
    this.title,
    required this.onActivity,
    this.onMenu,
    this.onNewChat,
  });

  final MukaiBot bot;
  final int activityCount;
  final String? title;
  final VoidCallback onActivity;
  final VoidCallback? onMenu;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 8),
      child: Row(
        children: <Widget>[
          MukaiIconButton(
            icon: onMenu == null
                ? Icons.arrow_back_ios_new_rounded
                : Icons.view_sidebar_outlined,
            tooltip: onMenu == null ? 'Back' : 'Open sidebar',
            border: false,
            iconSize: 17,
            onTap: () {
              Haptics.select();
              if (onMenu != null) {
                onMenu!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          GhostAvatar(mascot: bot.mascot, identity: bot.identity, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title ?? bot.name,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (bot.isMain) ...<Widget>[
                      const SizedBox(width: 5),
                      Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: colors.identity(BotIdentity.scout).mark,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Row(
                  children: <Widget>[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: bot.running
                            ? const Color(0xFF4CB07F)
                            : colors.textSoft,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        bot.role,
                        style: text.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          MukaiIconButton(
            icon: Icons.dashboard_outlined,
            tooltip: 'Activity',
            border: false,
            onTap: onActivity,
          ),
          if (onNewChat != null)
            MukaiIconButton(
              icon: Icons.edit_square,
              tooltip: 'New chat',
              border: false,
              onTap: onNewChat,
            ),
        ],
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return PressableScale(
      scale: 0.9,
      onTap: () {
        Haptics.select();
        onTap();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.card,
          shape: BoxShape.circle,
          border: Border.all(color: colors.hairlineStrong),
          boxShadow: MukaiShadows.card(colors.brightness),
        ),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 19,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
