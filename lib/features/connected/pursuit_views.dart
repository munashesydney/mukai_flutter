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
  final instant = DateTime.tryParse(words(value));
  if (instant == null) return 'Not scheduled';
  final zone = MukaiScope.sessionOf(context).workspace.timeZone;
  final date = WorkspaceTime.local(instant, zone);
  final now = DateTime.now();
  final difference = WorkspaceTime.dayDifference(instant, now, zone);
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  if (difference == -1) return 'Yesterday';
  return MaterialLocalizations.of(context).formatMediumDate(date);
}

String _clock(BuildContext context, dynamic value) {
  final instant = DateTime.tryParse(words(value));
  final date = instant == null
      ? null
      : WorkspaceTime.local(
          instant,
          MukaiScope.sessionOf(context).workspace.timeZone,
        );
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
  const _PursuitsScreen({required this.onOpenRun});
  final OpenPursuitRun onOpenRun;
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
                                onOpenRun: onOpenRun,
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
  const _PursuitPage({required this.id, required this.onOpenRun});
  final String id;
  final OpenPursuitRun onOpenRun;
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

  void _run(String id) {
    final onOpen = widget.onOpenRun;
    final pursuitId = widget.id;
    Navigator.of(context).removeRoute(ModalRoute.of(context)!);
    onOpen(pursuitId, id);
  }

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
      leading: MukaiGlassPill.circle(child: const BackButton()),
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
  });
  final String title, body;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      MukaiDisclosure(
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
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

/// Uses the shared conversation UI with the controls and outcome of this run.
class PursuitRunChat extends StatefulWidget {
  const PursuitRunChat({
    super.key,
    required this.pursuitId,
    required this.runId,
    required this.joined,
    required this.onJoin,
    required this.onMenu,
    required this.onHistory,
    required this.onOpenSource,
  });

  final String pursuitId, runId;
  final bool joined;
  final VoidCallback onJoin, onMenu, onHistory;
  final Future<void> Function(NotificationSource) onOpenSource;

  @override
  State<PursuitRunChat> createState() => _PursuitRunChatState();
}

class _PursuitRunChatState extends State<PursuitRunChat> {
  bool _retrying = false;
  String get _path => '/pursuits/${encoded(widget.pursuitId)}';

  Future<void> _retry(Future<void> Function() reload) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await connectedRequest(
        context,
        '$_path/retry',
        method: 'POST',
        body: {'runId': widget.runId},
      );
      if (mounted) await reload();
    } catch (error) {
      if (mounted) connectionNotice(context, error);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ConnectedAsync(
    refreshInterval: const Duration(seconds: 5),
    load: () =>
        connectedRequest(context, '$_path/run?runId=${encoded(widget.runId)}'),
    builder: (context, data, reload) {
      final run = object(data), snapshot = object(run['snapshot']);
      final conversationId = words(run['conversationId']);
      final status = words(run['status']);
      final session = MukaiScope.sessionOf(context);
      final bot = session.remote!.botById(words(snapshot['ownerBotId']));
      if (conversationId.isEmpty) {
        return const Center(child: Text('This run has no conversation.'));
      }
      return ChatScreen(
        key: ValueKey(conversationId),
        bot: bot,
        conversationId: conversationId,
        kind: 'pursuit_run',
        title: words(snapshot['name'], 'Pursuit run'),
        joined: widget.joined,
        onJoin: widget.onJoin,
        onMenu: widget.onMenu,
        onOpenSource: widget.onOpenSource,
        run: ChatRun(
          id: widget.runId,
          status: status,
          onHistory: widget.onHistory,
          onRetry:
              bot.id.isNotEmpty &&
                  !_retrying &&
                  ['failed', 'stopped', 'interrupted'].contains(status)
              ? () => _retry(reload)
              : null,
          outcome: _RunOutcome(run: run, snapshot: snapshot),
        ),
      );
    },
  );
}

class _RunOutcome extends StatelessWidget {
  const _RunOutcome({required this.run, required this.snapshot});
  final JsonMap run, snapshot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = words(run['summary']);
    final error = words(run['error']);
    final objective = words(snapshot['objective']);
    final criteria = words(snapshot['successCriteria']);
    return ListView(
      key: const PageStorageKey('run-outcome'),
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
      children: [
        Text('Run outcome', style: text.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${_statusLabel(words(run['status']))} · '
          '${run['trigger'] == 'manual' ? 'Started by you' : 'Started on schedule'} · '
          '${_when(context, run['startedAt'])}',
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              error,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        _ReadingText(
          summary.isEmpty
              ? 'A summary will appear when this run finishes.'
              : summary,
        ),
        if (objective.isNotEmpty) ...[
          const SizedBox(height: 20),
          _ReadingDisclosure(title: 'Full objective', body: objective),
        ],
        if (criteria.isNotEmpty)
          _ReadingDisclosure(title: 'Success criteria', body: criteria),
      ],
    );
  }
}
