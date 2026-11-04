part of 'connected_features_screen.dart';

String _preview(dynamic value, [int max = 250]) =>
    Format.snippet(words(value), max: max);
String _statusLabel(String value) => switch (value) {
  'waiting_for_you' => 'Needs you',
  'complete' || 'completed' => 'Complete',
  'active' => 'Active',
  'waiting' => 'Scheduled',
  'running' => 'Running',
  'paused' => 'Paused',
  'blocked' => 'Blocked',
  'failed' => 'Failed',
  'stopped' => 'Stopped',
  'interrupted' => 'Interrupted',
  _ => label(value),
};
String _day(BuildContext context, dynamic value) {
  final date = DateTime.tryParse(words(value))?.toLocal();
  if (date == null) return 'Not scheduled';
  final now = DateTime.now();
  final difference = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  if (difference == -1) return 'Yesterday';
  return MaterialLocalizations.of(context).formatMediumDate(date);
}

String _clock(BuildContext context, dynamic value) {
  final date = DateTime.tryParse(words(value))?.toLocal();
  return date == null
      ? ''
      : MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(date),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        );
}

String _when(BuildContext context, dynamic value) =>
    DateTime.tryParse(words(value)) == null
    ? 'Not scheduled'
    : '${_day(context, value)} · ${_clock(context, value)}';

class _PursuitStatus extends StatelessWidget {
  const _PursuitStatus(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final problem = ['failed', 'blocked', 'interrupted'].contains(status);
    final color = problem
        ? Theme.of(context).colorScheme.error
        : ['paused', 'stopped'].contains(status)
        ? colors.textMuted
        : colors.accentInk;
    final icon = switch (status) {
      'complete' || 'completed' => Icons.check_circle_outline_rounded,
      'paused' => Icons.pause_circle_outline_rounded,
      'running' => Icons.autorenew_rounded,
      'failed' || 'blocked' || 'interrupted' => Icons.error_outline_rounded,
      'waiting_for_you' => Icons.front_hand_outlined,
      _ => Icons.schedule_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            _statusLabel(status),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PursuitOwner extends StatelessWidget {
  const _PursuitOwner(this.id);
  final dynamic id;
  @override
  Widget build(BuildContext context) {
    final bot = MukaiScope.sessionOf(
      context,
    ).bots.where((b) => b.id == id).firstOrNull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GhostAvatar(
          mascot: bot?.mascot ?? Mascot.defaultBot,
          identity: bot?.identity ?? BotIdentity.mukai,
          size: 23,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            bot?.name ?? 'Companion unavailable',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: MukaiColors.of(context).textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PursuitsScreen extends StatelessWidget {
  const _PursuitsScreen({required this.onOpenConversation});
  final ValueChanged<Conversation> onOpenConversation;
  @override
  Widget build(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    return ConnectedAsync(
      key: ValueKey('pursuits:${session.workspace.id}'),
      refreshInterval: const Duration(seconds: 5),
      load: () =>
          connectedRequest(context, '/pursuits?${workspaceQuery(context)}'),
      builder: (context, data, reload) {
        final rows = objects(data);
        final active = rows
            .where((p) => ['active', 'waiting'].contains(p['status']))
            .length;
        return RefreshIndicator.adaptive(
          onRefresh: reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pursuits',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A little momentum, even while you’re away.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (rows.isNotEmpty) ...[
                        const SizedBox(height: 19),
                        Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          children: [
                            Text(
                              '$active moving forward',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: MukaiColors.of(context).accentInk,
                                  ),
                            ),
                            Text(
                              '· ${rows.length} total',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (rows.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: ConnectedEmpty(
                    title: 'Something worth pursuing.',
                    body:
                        'Ask a companion to keep working toward a goal. Its progress will find a home here.',
                    icon: Icons.track_changes_rounded,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    MediaQuery.paddingOf(context).bottom + 28,
                  ),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final pursuit = rows[index];
                      return _PursuitCard(
                        pursuit: pursuit,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => _PursuitPage(
                                id: words(pursuit['id']),
                                onOpenConversation: onOpenConversation,
                              ),
                            ),
                          );
                          if (context.mounted) await reload();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PursuitCard extends StatelessWidget {
  const _PursuitCard({required this.pursuit, required this.onTap});
  final JsonMap pursuit;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: MukaiCard(
        radius: 22,
        elevated: false,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _PursuitStatus(words(pursuit['status'])),
                const Spacer(),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 17,
                  color: colors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              words(pursuit['name'], 'Untitled pursuit'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _preview(pursuit['objective']),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 17),
            const SoftDivider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _PursuitOwner(pursuit['ownerBotId'])),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _when(context, pursuit['nextRunAt']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: text.labelSmall?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PursuitPage extends StatefulWidget {
  const _PursuitPage({required this.id, required this.onOpenConversation});
  final String id;
  final ValueChanged<Conversation> onOpenConversation;
  @override
  State<_PursuitPage> createState() => _PursuitPageState();
}

class _PursuitPageState extends State<_PursuitPage> {
  bool _busy = false;
  JsonMap _pursuit = {};
  Future<void> Function()? _reload;

  List<PopupMenuEntry<String>> _menu(BuildContext context) {
    final status = words(_pursuit['status']);
    final scheduled = ['active', 'waiting'].contains(status);
    final current = words(_pursuit['currentRunId']);
    final owner = MukaiScope.sessionOf(
      context,
    ).bots.any((b) => b.id == _pursuit['ownerBotId']);
    return [
      if (status != 'completed') ...[
        PopupMenuItem(
          value: 'run',
          enabled: !_busy && owner && (scheduled || current.isNotEmpty),
          child: Text(current.isEmpty ? 'Run now' : 'View current run'),
        ),
        PopupMenuItem(
          value: 'status',
          enabled: !_busy && owner,
          child: Text(scheduled ? 'Pause' : 'Resume'),
        ),
        const PopupMenuDivider(),
      ],
      PopupMenuItem(
        value: 'delete',
        enabled: !_busy,
        child: const Text('Delete pursuit'),
      ),
    ];
  }

  Future<void> _menuAction(String action) async {
    if (action == 'delete') {
      await _delete();
      return;
    }
    final reload = _reload;
    if (reload == null || _busy) return;
    if (action == 'run') {
      final current = words(_pursuit['currentRunId']);
      if (current.isNotEmpty) {
        _run(current);
      } else {
        await _action('/run', reload);
      }
    } else {
      final scheduled = ['active', 'waiting'].contains(_pursuit['status']);
      await _action(
        '/status',
        reload,
        method: 'PUT',
        body: {'status': scheduled ? 'paused' : 'active'},
      );
    }
  }

  Future<void> _action(
    String action,
    Future<void> Function() reload, {
    Object? body,
    String method = 'POST',
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await connectedRequest(
        context,
        '/pursuits/${encoded(widget.id)}$action',
        method: method,
        body: body,
      );
      await reload();
    } catch (error) {
      if (mounted) connectionNotice(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _run(String id) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _RunPage(
        pursuitId: widget.id,
        runId: id,
        onOpenConversation: widget.onOpenConversation,
      ),
    ),
  );

  Future<void> _delete() async {
    if (!await confirmRemoval(
      context,
      'Delete this pursuit?',
      'This removes the pursuit and its run history from Mukai.',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await connectedRequest(
        context,
        '/pursuits/${encoded(widget.id)}',
        method: 'DELETE',
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) connectionNotice(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pursuit'),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Pursuit options',
          onSelected: _menuAction,
          itemBuilder: _menu,
        ),
      ],
    ),
    body: ConnectedAsync(
      refreshInterval: const Duration(seconds: 5),
      load: () => connectedRequest(context, '/pursuits/${encoded(widget.id)}'),
      builder: (context, data, reload) {
        final pursuit = object(object(data)['pursuit']);
        _pursuit = pursuit;
        _reload = reload;
        final runs = objects(object(data)['runs']);
        final status = words(pursuit['status']);
        final current = words(pursuit['currentRunId']);
        final colors = MukaiColors.of(context);
        final text = Theme.of(context).textTheme;
        return RefreshIndicator.adaptive(
          onRefresh: reload,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              22,
              14,
              22,
              MediaQuery.paddingOf(context).bottom + 32,
            ),
            children: [
              Row(
                children: [
                  Expanded(child: _PursuitOwner(pursuit['ownerBotId'])),
                  _PursuitStatus(status),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                words(pursuit['name'], 'Pursuit'),
                style: text.headlineMedium?.copyWith(
                  fontSize: 28,
                  height: 1.15,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _preview(pursuit['objective'], 320),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.accentSoft.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 21,
                      color: colors.accentInk,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.isNotEmpty
                                ? 'A run is in progress'
                                : 'Next wake',
                            style: text.labelSmall?.copyWith(
                              color: colors.accentInk,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            current.isNotEmpty
                                ? 'Working toward your goal'
                                : _when(context, pursuit['nextRunAt']),
                            style: text.titleSmall,
                          ),
                          if (words(pursuit['nextRunReason']).isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _preview(pursuit['nextRunReason']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 25),
              const _SectionTitle('Working memory'),
              const SizedBox(height: 10),
              MukaiCard(
                elevated: false,
                radius: 20,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _WorkpadPage(pursuitId: widget.id),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.accentSoft,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.notes_rounded,
                        color: colors.accentInk,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Workpad', style: text.titleSmall),
                          const SizedBox(height: 3),
                          Text(
                            'Notes, decisions & next steps',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 27),
              Row(
                children: [
                  const Expanded(child: _SectionTitle('Run history')),
                  Text(
                    '${runs.length}',
                    style: text.labelMedium?.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (runs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'The first run is still ahead.',
                    style: text.bodySmall,
                  ),
                ),
              for (final run in runs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RunCard(
                    run: run,
                    onTap: () => _run(words(run['id'])),
                  ),
                ),
              const SizedBox(height: 17),
              _ReadingDisclosure(
                key: ValueKey('objective-${widget.id}'),
                title: 'Full objective',
                body: words(pursuit['objective']),
              ),
              _ReadingDisclosure(
                key: ValueKey('success-${widget.id}'),
                title: 'Success criteria',
                body: words(pursuit['successCriteria']),
              ),
              if (pursuit['deadline'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Deadline · ${_when(context, pursuit['deadline'])}',
                    style: text.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
  );
}

class _ReadingText extends StatelessWidget {
  const _ReadingText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SelectionArea(
    child: MarkdownBody(
      data: text,
      imageBuilder: (uri, title, alt) =>
          parseResponseReference(uri.toString()) != null
          ? ChatImagePreview(href: uri.toString(), name: alt ?? 'Image')
          : Text(alt ?? '[Image link]'),
      onTapLink: (label, href, _) {
        if (href != null) openChatContent(context, href, name: label);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
        codeblockDecoration: BoxDecoration(
          color: MukaiColors.of(context).cardMuted,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}

class _ReadingDisclosure extends StatelessWidget {
  const _ReadingDisclosure({
    super.key,
    required this.title,
    required this.body,
    this.preview,
  });
  final String title, body;
  final String? preview;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      MukaiDisclosure(
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        preview: preview == null
            ? null
            : Text(
                preview!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
        builder: (_) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _ReadingText(body),
        ),
      ),
      const SoftDivider(),
    ],
  );
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, required this.onTap});
  final JsonMap run;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context), text = Theme.of(context).textTheme;
    return Semantics(
      key: ValueKey('pursuit-run-${run['id']}'),
      button: true,
      label: 'Open pursuit run',
      child: MukaiCard(
        radius: 18,
        elevated: false,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _when(context, run['startedAt']),
                    style: text.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textMuted,
                  size: 19,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _preview(run['summary'], 230).isEmpty
                  ? 'Your companion is working on this run.'
                  : _preview(run['summary'], 230),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _PursuitStatus(words(run['status'])),
                const SizedBox(width: 9),
                Text(
                  run['trigger'] == 'manual' ? 'Manual run' : 'Scheduled run',
                  style: text.labelSmall?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunPage extends StatefulWidget {
  const _RunPage({
    required this.pursuitId,
    required this.runId,
    required this.onOpenConversation,
  });
  final String pursuitId, runId;
  final ValueChanged<Conversation> onOpenConversation;
  @override
  State<_RunPage> createState() => _RunPageState();
}

class _RunPageState extends State<_RunPage> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pursuit run')),
    body: ConnectedAsync(
      refreshInterval: const Duration(seconds: 5),
      load: () async {
        final run = object(
          await connectedRequest(
            context,
            '/pursuits/${encoded(widget.pursuitId)}/run?runId=${encoded(widget.runId)}',
          ),
        );
        if (!context.mounted) return null;
        final messages = words(run['conversationId']).isEmpty
            ? <JsonMap>[]
            : objects(
                await connectedRequest(
                  context,
                  '/conversations/${encoded(run['conversationId'])}/messages',
                ),
              );
        return {'run': run, 'messages': messages};
      },
      builder: (context, data, reload) {
        final run = object(object(data)['run']),
            snapshot = object(run['snapshot']);
        final status = words(run['status']),
            conversationId = words(run['conversationId']);
        final session = MukaiScope.sessionOf(context);
        final colors = MukaiColors.of(context),
            text = Theme.of(context).textTheme;
        final messages = objects(object(data)['messages'])
            .map((m) => session.remote!.messageFromJson(m, conversationId))
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _PursuitOwner(snapshot['ownerBotId'])),
                      _PursuitStatus(status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _when(context, run['startedAt']),
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    run['trigger'] == 'manual'
                        ? 'Started by you'
                        : 'Started on schedule',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (conversationId.isNotEmpty)
                        ConnectedAction(
                          label: 'Open conversation',
                          icon: Icons.arrow_outward_rounded,
                          tonal: true,
                          action: () async {
                            final conversation = Conversation(
                              id: conversationId,
                              title: words(snapshot['name'], 'Pursuit run'),
                              botId: words(snapshot['ownerBotId']),
                              updatedAt:
                                  DateTime.tryParse(words(run['startedAt'])) ??
                                  DateTime.now(),
                              kind: 'pursuit_run',
                            );
                            Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst);
                            widget.onOpenConversation(conversation);
                          },
                        ),
                      if (status == 'running')
                        ConnectedAction(
                          label: 'Stop run',
                          tonal: true,
                          action: () async {
                            await connectedRequest(
                              context,
                              '/conversations/${encoded(conversationId)}/stop',
                              method: 'POST',
                            );
                            if (context.mounted) await reload();
                          },
                        ),
                      if (['failed', 'stopped', 'interrupted'].contains(status))
                        ConnectedAction(
                          label: 'Retry run',
                          action: () async {
                            final retried = object(
                              await connectedRequest(
                                context,
                                '/pursuits/${encoded(widget.pursuitId)}/retry',
                                method: 'POST',
                                body: {'runId': widget.runId},
                              ),
                            );
                            if (!context.mounted) return;
                            await Navigator.pushReplacement(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => _RunPage(
                                  pursuitId: widget.pursuitId,
                                  runId: words(retried['id']),
                                  onOpenConversation: widget.onOpenConversation,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: colors.cardMuted,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        for (final (index, name) in [
                          (0, 'Conversation'),
                          (1, 'Summary'),
                        ])
                          Expanded(
                            child: PressableScale(
                              onTap: () => setState(() => _tab = index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: _tab == index
                                      ? colors.card
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  name,
                                  textAlign: TextAlign.center,
                                  style: text.labelMedium?.copyWith(
                                    color: _tab == index
                                        ? colors.ink
                                        : colors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tab == 1
                  ? SingleChildScrollView(
                      key: const PageStorageKey('run-summary'),
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (run['error'] != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                words(run['error']),
                                style: text.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          _ReadingText(
                            words(run['summary']).isEmpty
                                ? 'A summary will appear when this run finishes.'
                                : words(run['summary']),
                          ),
                        ],
                      ),
                    )
                  : messages.isEmpty
                  ? const ConnectedEmpty(
                      title: 'The conversation starts here.',
                      body:
                          'Messages from this run will appear as your companion works.',
                      icon: Icons.forum_outlined,
                    )
                  : ListView.builder(
                      key: const PageStorageKey('run-messages'),
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
                      itemCount: messages.length,
                      itemBuilder: (context, index) =>
                          _RunMessage(message: messages[index]),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

/// Historical run messages never act on the shell's currently selected chat.
class _RunMessage extends StatelessWidget {
  const _RunMessage({required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final prompt = message.blocks
        .whereType<TextBlock>()
        .map((b) => b.text)
        .join('\n\n');
    if (message.fromUser && prompt.length > 600) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: ChatContentScope(
          conversationId: message.conversationId ?? 'bot-${message.botId}',
          messageId: message.id,
          child: _ReadingDisclosure(
            key: ValueKey('run-instructions-${message.id}'),
            title: 'Run instructions',
            body: prompt,
            preview: _preview(prompt, 160),
          ),
        ),
      );
    }
    return MessageView(
      message: message,
      bots: MukaiScope.sessionOf(context).bots,
    );
  }
}
