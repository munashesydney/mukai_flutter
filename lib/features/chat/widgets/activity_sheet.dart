/// Chat activity as a draggable bottom sheet.
///
/// The desktop shows Bots / Links / Outputs / Changes in a right rail. Here the
/// same sections live in a sheet with two snap points, so a thumb reaches the
/// details without leaving the conversation.
library;

import 'package:flutter/material.dart';
import 'open_content.dart';

import '../../../core/format.dart';
import '../../../design/appearance.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../../../domain/models.dart';

class ActivitySheet extends StatelessWidget {
  const ActivitySheet({
    super.key,
    required this.activity,
    required this.bots,
    this.onOpenBot,
  });

  final ChatActivity activity;
  final List<MukaiBot> bots;
  final ValueChanged<MukaiBot>? onOpenBot;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.28,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const <double>[0.28, 0.62, 0.92],
      builder: (BuildContext context, ScrollController controller) {
        return ColoredBox(
          color: colors.canvas,
          child: ListView(
            controller: controller,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: MukaiSpace.xxxl),
            children: <Widget>[
              const SheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MukaiSpace.screen,
                  MukaiSpace.md,
                  MukaiSpace.screen,
                  0,
                ),
                child: Row(
                  children: <Widget>[
                    Text('Activity', style: text.titleLarge),
                    const Spacer(),
                    IdentityChip(label: '${activity.total} items', dense: true),
                  ],
                ),
              ),
              if (activity.bots.isNotEmpty) ...<Widget>[
                SectionHeader(
                  label: 'Bots',
                  count: activity.bots.length,
                  padding: const EdgeInsets.fromLTRB(
                    MukaiSpace.screen,
                    MukaiSpace.lg,
                    MukaiSpace.md,
                    MukaiSpace.xs,
                  ),
                ),
                for (final String botId in activity.bots) _botRow(botId),
              ],
              if (activity.links.isNotEmpty) ...<Widget>[
                SectionHeader(
                  label: 'Links',
                  count: activity.links.length,
                  padding: const EdgeInsets.fromLTRB(
                    MukaiSpace.screen,
                    MukaiSpace.lg,
                    MukaiSpace.md,
                    MukaiSpace.xs,
                  ),
                ),
                for (final ActivityLink link in activity.links) _linkRow(link),
              ],
              if (activity.outputs.isNotEmpty) ...<Widget>[
                SectionHeader(
                  label: 'Outputs',
                  count: activity.outputs.length,
                  padding: const EdgeInsets.fromLTRB(
                    MukaiSpace.screen,
                    MukaiSpace.lg,
                    MukaiSpace.md,
                    MukaiSpace.xs,
                  ),
                ),
                for (final ActivityOutput output in activity.outputs)
                  _outputRow(output),
              ],
              if (activity.changes.isNotEmpty) ...<Widget>[
                SectionHeader(
                  label: 'Changes',
                  count: activity.changes.length,
                  padding: const EdgeInsets.fromLTRB(
                    MukaiSpace.screen,
                    MukaiSpace.lg,
                    MukaiSpace.md,
                    MukaiSpace.xs,
                  ),
                ),
                for (final ActivityChange change in activity.changes)
                  _changeRow(change),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MukaiSpace.screen,
                    MukaiSpace.sm,
                    MukaiSpace.screen,
                    0,
                  ),
                  child: Text(
                    'Latest saved edit for each file',
                    style: text.bodySmall?.copyWith(color: colors.textSoft),
                  ),
                ),
              ],
              if (activity.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(MukaiSpace.xxxl),
                  child: MukaiEmptyState(
                    title: 'Nothing saved yet',
                    body:
                        'Bots, links, outputs and changes from this run will '
                        'collect here.',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _botRow(String botId) {
    final MukaiBot bot = bots.firstWhere(
      (MukaiBot candidate) => candidate.id == botId,
      orElse: () => const MukaiBot(
        id: '',
        name: 'Mukai',
        role: 'Companion',
        mascot: 'mukai-logo',
        identity: BotIdentity.mukai,
        running: false,
      ),
    );
    return Builder(
      builder: (BuildContext context) {
        final MukaiColors colors = MukaiColors.of(context);
        final TextTheme text = Theme.of(context).textTheme;
        return PressableScale(
          scale: 0.99,
          onTap: onOpenBot == null
              ? null
              : () {
                  Haptics.select();
                  onOpenBot!(bot);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MukaiSpace.screen,
              vertical: 9,
            ),
            child: Row(
              children: <Widget>[
                GhostAvatar(
                  mascot: bot.mascot,
                  identity: bot.identity,
                  size: 32,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(bot.name, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        bot.role,
                        style: text.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textSoft,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _linkRow(ActivityLink link) {
    return Builder(
      builder: (BuildContext context) {
        final MukaiColors colors = MukaiColors.of(context);
        return PressableScale(
          scale: 0.99,
          onTap: () => openChatContent(context, link.title),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MukaiSpace.screen,
              vertical: 9,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.language_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        link.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CB07F),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            link.state,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 15,
                  color: colors.textSoft,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _outputRow(ActivityOutput output) {
    final bool isImage = output.kind.contains('image');
    return Builder(
      builder: (BuildContext context) {
        final MukaiColors colors = MukaiColors.of(context);
        return PressableScale(
          scale: 0.99,
          onTap: output.id == null
              ? null
              : () => openChatContent(
                  context,
                  'mukai-artifact:${output.id}',
                  name: output.name,
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MukaiSpace.screen,
              vertical: 9,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  isImage ? Icons.image_outlined : Icons.description_outlined,
                  size: 18,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        Format.compactFileName(output.name),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        output.kind,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: colors.textSoft,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _changeRow(ActivityChange change) {
    return Builder(
      builder: (BuildContext context) {
        final MukaiColors colors = MukaiColors.of(context);
        final TextTheme text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MukaiSpace.screen,
            vertical: 9,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.edit_document, size: 18, color: colors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(change.file, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      change.path,
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                Format.diffSummary(change.added, change.removed),
                style: text.labelMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
