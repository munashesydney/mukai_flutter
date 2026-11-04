/// Renders each rich response block the way the desktop chat does, in a form
/// that reads well at phone width.
///
/// One widget per block kind, dispatched by an exhaustive `switch` over the
/// sealed [ChatBlock] hierarchy — adding a block type becomes a compile error
/// until it is handled here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'open_content.dart';
import 'file_preview.dart';
import '../../../core/response_reference.dart';

import '../../../design/appearance.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../../../design/disclosure.dart';
import '../../../domain/models.dart';
import 'revenue_chart.dart';

class ChatBlockView extends StatelessWidget {
  const ChatBlockView({
    super.key,
    required this.block,
    required this.bots,
    this.onApproval,
  });

  final ChatBlock block;
  final List<MukaiBot> bots;
  final void Function(ApprovalBlock approval, bool approved)? onApproval;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      final TextBlock b => _TextBody(text: b.text),
      final HeadingBlock b => _Heading(text: b.text),
      final BulletBlock b => _Bullets(items: b.items),
      final ToolBlock b => _ToolCard(block: b),
      final CompactionBlock b => _CompactionStatus(block: b),
      ApprovalBlock() => const SizedBox.shrink(),
      final ChartBlock b => _ChartCard(block: b),
      final TableBlock b => _TableCard(block: b),
      final LinkBlock b => _LinkRow(block: b),
      final SubBotBlock b => _SubBotRow(block: b, bots: bots),
    };
  }
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

class _TextBody extends StatelessWidget {
  const _TextBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.62),
      ),
      imageBuilder: (uri, title, alt) =>
          parseResponseReference(uri.toString()) != null
          ? ChatImagePreview(
              href: uri.toString(),
              name: alt?.isNotEmpty == true ? alt! : 'Image',
            )
          : Text(alt == null ? '[Image link]' : '[$alt]'),
      onTapLink: (label, href, title) {
        if (href != null) openChatContent(context, href, name: label);
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colors.textBody, height: 1.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 10),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(child: Text(item, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tool activity and approvals
// ---------------------------------------------------------------------------

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.block});
  final ToolBlock block;
  @override
  Widget build(BuildContext context) {
    final label = Text(
      block.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: MukaiColors.of(context).textMuted),
    );
    final disclosure = MukaiDisclosure(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (block.state == ToolState.error) ...[
            Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: block.state == ToolState.running
                ? MukaiShimmerText(child: label)
                : label,
          ),
        ],
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 12),
        child: SelectableText(
          block.detail.isEmpty ? 'No additional details.' : block.detail,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
        ),
      ),
    );
    if (block.previewHref == null) return disclosure;
    // Desktop keeps image rows as a plain button that opens the preview;
    // the picture never sits inline in the chat transcript.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        disclosure,
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openChatContent(
              context,
              block.previewHref!,
              name: 'Image',
              image: true,
            ),
            icon: const Icon(Icons.image_outlined, size: 16),
            label: const Text('View image'),
          ),
        ),
      ],
    );
  }
}

class _CompactionStatus extends StatelessWidget {
  const _CompactionStatus({required this.block});
  final CompactionBlock block;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (block.state) {
          'compacting' => 'Compacting context…',
          'complete' => 'Context compacted',
          'failed' => 'Context compaction failed',
          _ => 'Context compaction interrupted',
        }, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          block.state == 'complete' && block.after != null
              ? '${block.before} → ${block.after} estimated context tokens. Original messages are kept.'
              : block.state == 'compacting'
              ? 'Preserving working memory before continuing. Original messages are kept.'
              : 'Original messages are kept. Retry to resume.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.block});
  final ChartBlock block;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return MukaiCard(
      padding: const EdgeInsets.all(MukaiSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(block.title, style: text.titleSmall)),
              if (block.downloadable)
                PressableScale(
                  onTap: Haptics.select,
                  scale: 0.94,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.download_rounded,
                        size: 14,
                        color: colors.accentInk,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Download data',
                        style: text.labelMedium?.copyWith(
                          color: colors.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: MukaiSpace.md),
          MukaiBarChart(block: block),
        ],
      ),
    );
  }
}

/// Collapsible data table — the desktop's `View data table` disclosure.
class _TableCard extends StatefulWidget {
  const _TableCard({required this.block});
  final TableBlock block;

  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PressableScale(
          onTap: () {
            Haptics.select();
            setState(() => _open = !_open);
          },
          scale: 0.98,
          child: Row(
            children: <Widget>[
              AnimatedRotation(
                turns: _open ? 0.25 : 0,
                duration: MukaiMotion.fast,
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 15,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'View data table',
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: MukaiMotion.normal,
          curve: MukaiMotion.curve,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: MukaiSpace.md),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(MukaiRadii.control),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.hairlineStrong),
                        borderRadius: BorderRadius.circular(MukaiRadii.control),
                      ),
                      child: Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: <TableRow>[
                          TableRow(
                            decoration: BoxDecoration(
                              color: colors.cardMuted,
                              border: Border(
                                bottom: BorderSide(color: colors.hairline),
                              ),
                            ),
                            children: <Widget>[
                              for (final String column in widget.block.columns)
                                _cell(column, text.labelMedium, pad: true),
                            ],
                          ),
                          for (final List<String> row in widget.block.rows)
                            TableRow(
                              children: <Widget>[
                                for (final String value in row)
                                  _cell(
                                    value,
                                    text.bodyMedium?.copyWith(
                                      fontFeatures: const <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                    pad: true,
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (widget.block.summary != null) ...<Widget>[
          const SizedBox(height: MukaiSpace.sm),
          Text(
            widget.block.summary!,
            style: text.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _cell(String value, TextStyle? style, {bool pad = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad ? 11 : 0, vertical: 9),
      child: Text(value, style: style),
    );
  }
}

// ---------------------------------------------------------------------------
// Links and delegated bots
// ---------------------------------------------------------------------------

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.block});
  final LinkBlock block;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    if (block.image) {
      return ChatImagePreview(href: block.url, name: block.title);
    }
    return PressableScale(
      onTap: () => openChatContent(context, block.url, name: block.title),
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: colors.cardMuted,
          borderRadius: BorderRadius.circular(MukaiRadii.control),
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.language_rounded, size: 17, color: colors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(block.title, style: text.titleSmall),
                  if (block.state != null) ...<Widget>[
                    const SizedBox(height: 3),
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
                          block.state!,
                          style: text.bodySmall?.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.arrow_outward_rounded, size: 15, color: colors.textSoft),
          ],
        ),
      ),
    );
  }
}

class _SubBotRow extends StatelessWidget {
  const _SubBotRow({required this.block, required this.bots});
  final SubBotBlock block;
  final List<MukaiBot> bots;

  @override
  Widget build(BuildContext context) {
    final MukaiBot bot = bots.firstWhere(
      (MukaiBot candidate) => candidate.id == block.botId,
      orElse: () => const MukaiBot(
        id: '',
        name: 'Companion',
        role: '',
        mascot: Mascot.defaultBot,
        identity: BotIdentity.neutral,
      ),
    );
    return _ToolCard(
      block: ToolBlock(
        label: '${bot.name} · ${block.status}',
        detail: block.result ?? 'Working with ${bot.name}.',
        state:
            [
              'running',
              'working',
              'streaming',
            ].contains(block.status.toLowerCase())
            ? ToolState.running
            : block.status == 'failed'
            ? ToolState.error
            : ToolState.done,
      ),
    );
  }
}
