/// Desktop-style bot groups with three more conversations per tap.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../design/appearance.dart';
import '../../../design/widgets.dart';
import '../../../domain/models.dart';

class BotConversationList extends StatefulWidget {
  const BotConversationList({
    super.key,
    required this.bots,
    required this.conversations,
    required this.onOpenConversation,
    required this.onNewConversation,
  });

  final List<MukaiBot> bots;
  final List<Conversation> conversations;
  final ValueChanged<Conversation> onOpenConversation;
  final ValueChanged<MukaiBot> onNewConversation;

  @override
  State<BotConversationList> createState() => _BotConversationListState();
}

class _BotConversationListState extends State<BotConversationList> {
  static const _pageSize = 3;
  String? _expandedBot;
  final Map<String, int> _visibleCounts = {};

  String? _group(Conversation chat) => switch (chat.kind) {
    'private' => chat.botId,
    'bot' => chat.botIds.length > 1 ? chat.botIds[1] : null,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = Theme.of(context).textTheme;
    final groups = <String, List<Conversation>>{};
    for (final chat in widget.conversations) {
      final group = _group(chat);
      if (group != null) (groups[group] ??= []).add(chat);
    }
    for (final chats in groups.values) {
      chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    final bots = [...widget.bots]
      ..sort((a, b) {
        final aDate = groups[a.id]?.firstOrNull?.updatedAt;
        final bDate = groups[b.id]?.firstOrNull?.updatedAt;
        final recent = aDate == null
            ? (bDate == null ? 0 : 1)
            : bDate == null
            ? -1
            : bDate.compareTo(aDate);
        if (recent != 0) return recent;
        if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
        return widget.bots.indexOf(a).compareTo(widget.bots.indexOf(b));
      });

    if (bots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Your bots will appear here.', style: text.bodySmall),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final bot in bots)
          Builder(
            builder: (context) {
              final open = _expandedBot == bot.id;
              final chats = groups[bot.id] ?? const <Conversation>[];
              final count = _visibleCounts[bot.id] ?? _pageSize;
              final remaining = chats.length - math.min(count, chats.length);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          expanded: open,
                          child: InkWell(
                            key: ValueKey('bot-group-${bot.id}'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Haptics.select();
                              setState(
                                () => _expandedBot = open ? null : bot.id,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 18,
                              ),
                              child: Row(
                                children: [
                                  GhostAvatar(
                                    mascot: bot.mascot,
                                    identity: bot.identity,
                                    size: 56,
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    open
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.chevron_right_rounded,
                                    size: 22,
                                    color: colors.textSoft,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      bot.name,
                                      style: text.titleLarge,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (bot.isMain) ...[
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Main bot',
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: 17,
                                        color: colors.textSoft,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      MukaiIconButton(
                        icon: Icons.add_comment_outlined,
                        tooltip: 'New conversation with ${bot.name}',
                        border: false,
                        size: 52,
                        iconSize: 26,
                        onTap: () => widget.onNewConversation(bot),
                      ),
                    ],
                  ),
                  if (open)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: colors.hairline),
                          ),
                        ),
                        padding: const EdgeInsets.only(left: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (chats.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Text(
                                  'No conversations yet.',
                                  style: text.bodySmall,
                                ),
                              ),
                            for (final chat in chats.take(count))
                              Semantics(
                                button: true,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => widget.onOpenConversation(chat),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            chat.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.bodyMedium,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          Format.relativeTime(chat.updatedAt),
                                          style: text.labelSmall?.copyWith(
                                            color: colors.textSoft,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (remaining > 0)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => setState(() {
                                    _visibleCounts[bot.id] = count + _pageSize;
                                  }),
                                  child: Text(
                                    'Load ${math.min(_pageSize, remaining)} more',
                                    style: text.bodySmall?.copyWith(
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
