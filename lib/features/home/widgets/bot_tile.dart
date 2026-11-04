/// Bot and conversation rows for the workspace home.
library;

import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../design/appearance.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../../../domain/models.dart';

/// One bot: mascot, name, role, main-bot star, presence and chevron.
class BotTile extends StatelessWidget {
  const BotTile({
    super.key,
    required this.bot,
    required this.onTap,
    this.subtitleOverride,
  });

  final MukaiBot bot;
  final VoidCallback onTap;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return PressableScale(
      onTap: () {
        Haptics.select();
        onTap();
      },
      scale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MukaiSpace.screen,
          vertical: 11,
        ),
        child: Row(
          children: <Widget>[
            GhostAvatar(
              mascot: bot.mascot,
              identity: bot.identity,
              size: 46,
              presence: bot.running,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          bot.name,
                          style: text.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (bot.isMain) ...<Widget>[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Main bot — starts with every tool',
                          child: Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: colors.identity(BotIdentity.scout).mark,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitleOverride ?? bot.role,
                    style: text.bodySmall?.copyWith(color: colors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 19, color: colors.textSoft),
          ],
        ),
      ),
    );
  }
}

/// A recent conversation, attributed to its bot.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.bot,
    required this.onTap,
  });

  final Conversation conversation;
  final MukaiBot bot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return PressableScale(
      onTap: () {
        Haptics.select();
        onTap();
      },
      scale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MukaiSpace.screen,
          vertical: 10,
        ),
        child: Row(
          children: <Widget>[
            GhostAvatar(mascot: bot.mascot, identity: bot.identity, size: 30),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          conversation.title,
                          style: text.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Format.relativeTime(conversation.updatedAt),
                        style: text.labelMedium?.copyWith(
                          color: colors.textSoft,
                        ),
                      ),
                    ],
                  ),
                  if (conversation.preview.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      Format.snippet(conversation.preview),
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
