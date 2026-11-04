part of 'connected_features_screen.dart';

/// The bot-update inbox, using the same notification endpoints as desktop.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key, required this.onOpenConversation});
  final ValueChanged<Conversation> onOpenConversation;
  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  int _pages = 1;
  String? _busy;

  Future<void> _act(
    String id,
    String action,
    Future<void> Function() reload,
  ) async {
    if (_busy != null) return;
    if (action == 'dismiss-all' &&
        !await confirmRemoval(
          context,
          'Dismiss all updates?',
          'This clears the updates in this workspace for everyone using it.',
          confirmLabel: 'Dismiss all',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = id);
    try {
      final result = await connectedRequest(
        context,
        '/notifications/${action == 'dismiss-all' ? 'dismiss-all' : '${encoded(id)}/$action'}?${workspaceQuery(context)}',
        method: 'POST',
      );
      if (!mounted) return;
      if (action == 'continue') {
        final conversation = MukaiScope.sessionOf(
          context,
        ).remote!.conversationFromJson(object(result));
        widget.onOpenConversation(conversation);
      } else {
        await reload();
      }
      if (mounted) await MukaiScope.sessionOf(context).refreshNotices();
    } catch (error) {
      if (mounted) connectionNotice(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    return ConnectedAsync(
      key: ValueKey('updates:${session.workspace.id}'),
      refreshInterval: const Duration(seconds: 5),
      load: () async {
        final pages = await Future.wait([
          for (var page = 0; page < _pages; page++)
            connectedRequest(
              context,
              '/notifications?${workspaceQuery(context)}&offset=${page * 30}',
            ),
        ]);
        final items = <String, JsonMap>{};
        for (final page in pages) {
          for (final item in objects(object(page)['items'])) {
            items[words(item['id'])] = item;
          }
        }
        return {...object(pages.first), 'items': items.values.toList()};
      },
      builder: (context, data, reload) {
        final inbox = object(data), items = objects(object(data)['items']);
        final text = Theme.of(context).textTheme,
            colors = MukaiColors.of(context);
        final total = inbox['total'] is num
            ? (inbox['total'] as num).toInt()
            : items.length;
        final unread = inbox['unread'] is num
            ? (inbox['unread'] as num).toInt()
            : 0;
        return RefreshIndicator.adaptive(
          onRefresh: reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Updates', style: text.headlineMedium),
                          ),
                          if (total > 0)
                            PopupMenuButton<String>(
                              tooltip: 'Update options',
                              onSelected: (_) =>
                                  _act('all', 'dismiss-all', reload),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'dismiss-all',
                                  enabled: _busy == null,
                                  child: const Text('Dismiss all'),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Findings and news from your companions’ autonomous work.',
                        style: text.bodySmall,
                      ),
                      if (unread > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            '$unread unread',
                            style: text.labelMedium?.copyWith(
                              color: colors.accentInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: ConnectedEmpty(
                    title: 'You’re all caught up',
                    body:
                        'Meaningful updates from your companions and pursuits will appear here.',
                    icon: Icons.notifications_none_rounded,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (_, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _UpdateCard(
                        key: ValueKey(items[index]['id']),
                        item: items[index],
                        busy: _busy != null,
                        onAction: (action) =>
                            _act(words(items[index]['id']), action, reload),
                      ),
                    ),
                  ),
                ),
              if (items.length < total)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: MukaiButton(
                      label: 'Load more updates',
                      variant: MukaiButtonVariant.quiet,
                      onPressed: _busy != null
                          ? null
                          : () async {
                              setState(() {
                                _pages++;
                                _busy = 'load-more';
                              });
                              try {
                                await reload();
                              } finally {
                                if (mounted) setState(() => _busy = null);
                              }
                            },
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 20,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UpdateCard extends StatefulWidget {
  const _UpdateCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onAction,
  });
  final JsonMap item;
  final bool busy;
  final ValueChanged<String> onAction;
  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final item = widget.item,
        colors = MukaiColors.of(context),
        text = Theme.of(context).textTheme;
    final bot = MukaiScope.sessionOf(
      context,
    ).bots.where((b) => b.id == item['botId']).firstOrNull;
    final unread = item['readAt'] == null;
    return MukaiCard(
      elevated: false,
      radius: 22,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GhostAvatar(
                          mascot: bot?.mascot ?? Mascot.defaultBot,
                          identity: bot?.identity ?? BotIdentity.mukai,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            words(item['botName'], 'Mukai'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium,
                          ),
                        ),
                        if (unread)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Semantics(
                              label: 'Unread update',
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.accentColor,
                                ),
                              ),
                            ),
                          ),
                        Text(
                          _day(context, item['createdAt']),
                          style: text.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      words(item['title'], 'An update for you'),
                      maxLines: _expanded ? null : 2,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    if (!_expanded)
                      Text(
                        _preview(item['message']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['sourceKind'] == 'pursuit_run'
                                ? 'Pursuit update'
                                : 'Companion update',
                            style: text.labelSmall,
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: colors.textMuted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          MukaiExpansion(
            expanded: _expanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SoftDivider(),
                  const SizedBox(height: 14),
                  _ReadingText(words(item['message'])),
                  const SizedBox(height: 16),
                  MukaiButton(
                    label: item['conversationId'] == null
                        ? 'Continue in chat'
                        : 'Open conversation',
                    icon: Icons.north_east_rounded,
                    compact: true,
                    variant: MukaiButtonVariant.tonal,
                    onPressed: widget.busy
                        ? null
                        : () => widget.onAction('continue'),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (unread)
                        TextButton(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onAction('read'),
                          child: const Text('Mark read'),
                        ),
                      TextButton(
                        onPressed: widget.busy
                            ? null
                            : () => widget.onAction('dismiss'),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
