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
import '../../design/glass.dart';
import '../../design/theme.dart';
import '../../design/widgets.dart';
import '../../domain/models.dart';
import 'widgets/activity_sheet.dart';
import 'widgets/approval_dock.dart';
import 'widgets/ai_queue_notice.dart';
import 'widgets/composer.dart';
import 'widgets/followup_queue.dart';
import 'widgets/message_bubble.dart';
import 'widgets/open_content.dart';

class ChatRun {
  const ChatRun({
    required this.id,
    required this.status,
    required this.outcome,
    required this.onHistory,
    this.onRetry,
  });

  final String id, status;
  final Widget outcome;
  final VoidCallback onHistory;
  final VoidCallback? onRetry;
  bool get active => status == 'running';
}

enum _ChatView { chat, artifacts, outcome }

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
    this.run,
    this.joined = false,
    this.onJoin,
    this.onOpenSource,
  });

  final MukaiBot bot;
  final String kind;
  final String? title;
  final List<String> memberBotIds;
  final String? conversationId;
  final bool fresh;
  final VoidCallback? onMenu;
  final VoidCallback? onNewChat;
  final ChatRun? run;
  final bool joined;
  final VoidCallback? onJoin;
  final Future<void> Function(NotificationSource)? onOpenSource;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  bool _showJump = false;
  bool _joiningReference = false;
  _ChatView _view = _ChatView.chat;

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
          viewOnly:
              widget.kind == 'pursuit_run' &&
              (widget.run == null || widget.bot.id.isEmpty),
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
        if (widget.conversationId != null &&
            widget.conversationId != session.conversationId) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final MukaiBot bot = session.loadingThreads ? widget.bot : session.bot;
        final run = widget.run;
        final active = run?.active ?? false;
        final canJoin = run != null && widget.bot.id.isNotEmpty;
        if (canJoin &&
            !widget.joined &&
            session.reference != null &&
            !_joiningReference) {
          _joiningReference = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onJoin?.call();
          });
        }
        final chat = _view == _ChatView.chat;
        final kickoff = run == null
            ? null
            : session.thread.where((m) => m.fromUser).firstOrNull;
        final kickoffText = kickoff?.blocks
            .whereType<TextBlock>()
            .map((b) => b.text)
            .join('\n');
        final automatic =
            kickoff != null &&
            (kickoff.requestId == run?.id ||
                RegExp(
                  r'^Pursuit: [\s\S]*? · Run \d+\nRun this pursuit autonomously\.',
                ).hasMatch(kickoffText ?? ''));
        final latestRequest = session.thread
            .where((m) => m.fromUser)
            .lastOrNull
            ?.requestId;
        final List<ChatMessage> thread = session.thread
            .where(
              (message) =>
                  (!automatic || message.id != kickoff.id) &&
                  (message.error != null ||
                      message.blocks.isEmpty ||
                      !message.blocks.every((block) => block is ApprovalBlock)),
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
                  activityCount: session.activity.total,
                  onActivity: _openActivity,
                  onMenu: widget.onMenu,
                  onNewChat: widget.onNewChat,
                  onRunHistory: run?.onHistory,
                ),
                if (run != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MukaiSpace.screen,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        for (final (view, label) in [
                          (_ChatView.chat, 'Chat'),
                          (_ChatView.artifacts, 'Artifacts'),
                          (_ChatView.outcome, 'Run outcome'),
                        ])
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: _view == view,
                              onSelected: (_) {
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() => _view = view);
                              },
                            ),
                          ),
                      ],
                    ),
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
                if (chat && session.api != null)
                  AIQueueNotice(
                    activity: session.aiActivity,
                    conversationId: session.conversationId ?? 'bot-${bot.id}',
                  ),
                if (!chat && run != null)
                  Expanded(
                    child: _view == _ChatView.outcome
                        ? run.outcome
                        : _RunArtifacts(
                            outputs: session.activity.outputs,
                            messages: thread,
                          ),
                  )
                else
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
                            title: run == null
                                ? 'A fresh start with ${bot.name}.'
                                : 'The run chat starts here.',
                            body: run == null
                                ? 'Bring a question, an idea, or something you’d like to move forward.'
                                : 'Messages will appear as your companion works.',
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      MessageView(
                                        timeZone: session.workspace.timeZone,
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
                                      if (thread[index].notificationSource
                                          case final source?)
                                        if (widget.onOpenSource != null)
                                          TextButton.icon(
                                            icon: const Icon(
                                              Icons.arrow_outward_rounded,
                                              size: 16,
                                            ),
                                            label: Text(
                                              source.isRun
                                                  ? 'Open original run'
                                                  : 'Open original conversation',
                                            ),
                                            onPressed: () =>
                                                widget.onOpenSource!(source),
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
                                          (widget.kind != 'pursuit_run' ||
                                              (canJoin &&
                                                  !active &&
                                                  thread[index].requestId ==
                                                      latestRequest &&
                                                  (!automatic ||
                                                      thread[index].requestId !=
                                                          kickoff
                                                              .requestId))) &&
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
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                          ),
                                          label: const Text('Retry response'),
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
                if (chat &&
                    pending.isEmpty &&
                    session.api != null &&
                    session.followups.isNotEmpty)
                  FollowupQueue(runActive: active),
                if (chat &&
                    pending.isEmpty &&
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
                if (run != null &&
                    (active || run.onRetry != null) &&
                    (!chat || !widget.joined || pending.isNotEmpty || !active))
                  TextButton.icon(
                    onPressed: active
                        ? (session.conversationId == widget.conversationId
                              ? session.stop
                              : null)
                        : run.onRetry,
                    icon: Icon(
                      active ? Icons.stop_rounded : Icons.refresh_rounded,
                    ),
                    label: Text(active ? 'Stop run' : 'Retry run'),
                  ),
                if (chat && pending.isNotEmpty)
                  SafeArea(top: false, child: ApprovalDock(requests: pending))
                else if (chat &&
                    widget.kind == 'pursuit_run' &&
                    (!canJoin || !widget.joined))
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: canJoin
                          ? OutlinedButton.icon(
                              onPressed: widget.onJoin,
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                              label: const Text('Jump in the chat'),
                            )
                          : const Text('Pursuit run · read only'),
                    ),
                  )
                else if (chat)
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
                      reference: session.reference,
                      onRemoveReference: () => session.setReference(null),
                      onDraftChanged: (text) =>
                          session.drafts[session.draftKey] = text,
                      allowQueue: session.api != null,
                      submitting: session.submittingFollowup,
                      onSubmit: session.api != null
                          ? (text) => session.send(text, queue: active)
                          : null,
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
                      responding: session.responding || active,
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
    required this.onActivity,
    this.onMenu,
    this.onNewChat,
    this.onRunHistory,
  });

  final MukaiBot bot;
  final int activityCount;
  final VoidCallback onActivity;
  final VoidCallback? onMenu;
  final VoidCallback? onNewChat;
  final VoidCallback? onRunHistory;

  @override
  Widget build(BuildContext context) {
    // ChatGPT-style: a transparent bar with the mascot floating in the middle
    // and the controls on their glass pills at the edges.
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            GhostAvatar(
              mascot: bot.mascot,
              identity: bot.identity,
              size: 36,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _SidebarToggle(onMenu: onMenu),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: MukaiGlassPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MukaiIconButton(
                      icon: Icons.dashboard_outlined,
                      tooltip: 'Activity',
                      border: false,
                      onTap: onActivity,
                    ),
                    if (onNewChat != null) ...<Widget>[
                      const MukaiGlassDivider(),
                      MukaiIconButton(
                        icon: Icons.edit_square,
                        tooltip: 'New chat',
                        border: false,
                        onTap: onNewChat,
                      ),
                    ],
                    if (onRunHistory != null) ...<Widget>[
                      const MukaiGlassDivider(),
                      MukaiIconButton(
                        icon: Icons.arrow_downward_rounded,
                        tooltip: 'Close run',
                        border: false,
                        onTap: onRunHistory,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarToggle extends StatelessWidget {
  const _SidebarToggle({this.onMenu});

  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    if (onMenu == null) {
      return MukaiIconButton(
        icon: Icons.arrow_back_ios_new_rounded,
        tooltip: 'Back',
        border: false,
        iconSize: 17,
        onTap: () {
          Haptics.select();
          Navigator.of(context).maybePop();
        },
      );
    }
    return MukaiGlassPill(
      child: MukaiIconButton(
        icon: Icons.view_sidebar_outlined,
        tooltip: 'Open sidebar',
        border: false,
        iconSize: 17,
        onTap: () {
          Haptics.select();
          onMenu!();
        },
      ),
    );
  }
}

class _RunArtifacts extends StatelessWidget {
  const _RunArtifacts({required this.outputs, required this.messages});

  final List<ActivityOutput> outputs;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final files = <String, LinkBlock>{
      for (final output in outputs)
        if (output.id case final id? when id.isNotEmpty)
          'mukai-artifact:$id': LinkBlock(
            url: 'mukai-artifact:$id',
            title: output.name,
            image: output.kind.startsWith('image/'),
          ),
      for (final message in messages)
        for (final attachment in message.blocks.whereType<LinkBlock>())
          if (attachment.url.startsWith('mukai-attachment:'))
            attachment.url: attachment,
    };
    if (files.isEmpty) {
      return const Center(child: Text('No artifacts in this run yet.'));
    }
    return ListView(
      padding: const EdgeInsets.all(MukaiSpace.screen),
      children: [
        for (final file in files.values)
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(file.title),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => openChatContent(
              context,
              file.url,
              name: file.title,
              image: file.image,
            ),
          ),
      ],
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
