/// Message rows — the user's own turn, and the bot's rich answer.
///
/// User turns get a filled bubble on the trailing edge; bot turns read like a
/// document (no bubble, blocks flush left) because most of what a bot returns is
/// tools, tables and cards rather than prose.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../design/appearance.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../../../design/disclosure.dart';
import '../../../domain/models.dart';
import 'chat_blocks.dart';
import 'open_content.dart';

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.message,
    required this.bots,
    this.onApproval,
  });

  final ChatMessage message;
  final List<MukaiBot> bots;
  final void Function(ApprovalBlock approval, bool approved)? onApproval;

  @override
  Widget build(BuildContext context) {
    return ChatContentScope(
      conversationId: message.conversationId ?? 'bot-${message.botId ?? ''}',
      messageId: message.id,
      child: message.fromUser
          ? _UserTurn(message: message)
          : _BotTurn(message: message, bots: bots, onApproval: onApproval),
    );
  }
}

class _UserTurn extends StatelessWidget {
  const _UserTurn({required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = message.blocks
        .whereType<TextBlock>()
        .map((b) => b.text)
        .join('\n\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: MukaiSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (text.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(6),
                  ),
                  border: Border.all(
                    color: colors.accentBorder.withValues(alpha: .7),
                  ),
                ),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.accentInk,
                    height: 1.55,
                  ),
                ),
              ),
            ),
          for (final file in message.blocks.whereType<LinkBlock>())
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: ChatBlockView(block: file, bots: const []),
              ),
            ),
        ],
      ),
    );
  }
}

class _BotTurn extends StatelessWidget {
  const _BotTurn({required this.message, required this.bots, this.onApproval});

  final ChatMessage message;
  final List<MukaiBot> bots;
  final void Function(ApprovalBlock approval, bool approved)? onApproval;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final MukaiBot bot = bots.firstWhere(
      (MukaiBot candidate) => candidate.id == message.botId,
      orElse: () => const MukaiBot(
        id: '',
        name: 'Mukai',
        role: 'Companion',
        mascot: 'mukai-logo',
        identity: BotIdentity.mukai,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: MukaiSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GhostAvatar(mascot: bot.mascot, identity: bot.identity, size: 26),
              const SizedBox(width: 8),
              Text(bot.name, style: text.titleSmall),
              if (bot.isMain) ...<Widget>[
                const SizedBox(width: 5),
                Icon(
                  Icons.star_rounded,
                  size: 12,
                  color: colors.identity(BotIdentity.scout).mark,
                ),
              ],
              const SizedBox(width: 7),
              Text(
                Format.clock(message.at),
                style: text.labelMedium?.copyWith(color: colors.textSoft),
              ),
            ],
          ),
          const SizedBox(height: MukaiSpace.sm),
          _ResponseBody(message: message, bots: bots, onApproval: onApproval),
        ],
      ),
    );
  }
}

class _ResponseBody extends StatelessWidget {
  const _ResponseBody({
    required this.message,
    required this.bots,
    this.onApproval,
  });
  final ChatMessage message;
  final List<MukaiBot> bots;
  final void Function(ApprovalBlock, bool)? onApproval;
  @override
  Widget build(BuildContext context) {
    final process = message.blocks.where((b) => b.isProcess).toList();
    final answer = message.blocks
        .where((b) => !b.isProcess && b is! ApprovalBlock)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (process.isNotEmpty || message.streaming)
          _WorkTranscript(
            key: ValueKey('work-${message.id}-${message.startedAt}'),
            message: message,
            blocks: process,
            bots: bots,
            continuing: message.streaming && answer.isEmpty,
          ),
        if (answer.isNotEmpty)
          _BlockStack(blocks: answer, bots: bots, onApproval: onApproval),
      ],
    );
  }
}

class _WorkTranscript extends StatefulWidget {
  const _WorkTranscript({
    super.key,
    required this.message,
    required this.blocks,
    required this.bots,
    this.continuing = false,
  });
  final ChatMessage message;
  final List<ChatBlock> blocks;
  final List<MukaiBot> bots;
  final bool continuing;
  @override
  State<_WorkTranscript> createState() => _WorkTranscriptState();
}

class _WorkTranscriptState extends State<_WorkTranscript> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(covariant _WorkTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.streaming != widget.message.streaming) _tick();
  }

  void _tick() {
    _timer?.cancel();
    if (widget.message.streaming) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final duration = Format.workDuration(
      message.startedAt ?? (message.streaming ? message.at : null),
      message.streaming ? DateTime.now() : message.finishedAt,
    );
    final verb = message.streaming
        ? 'Working'
        : switch (message.status) {
            'failed' => 'Failed',
            'stopped' => 'Stopped',
            'interrupted' => 'Interrupted',
            _ => 'Worked',
          };
    final compaction = widget.blocks.whereType<CompactionBlock>().lastOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MukaiDisclosure(
            title: Text(
              '$verb${duration == null ? '' : ' for $duration'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: MukaiColors.of(context).textMuted,
              ),
            ),
            builder: (_) => Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 10),
              child: widget.blocks.isEmpty
                  ? const Text('Thinking…')
                  : _WorkTranscriptContent(
                      blocks: widget.blocks,
                      bots: widget.bots,
                      continuing: widget.continuing,
                    ),
            ),
          ),
          if (compaction != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                switch (compaction.state) {
                  'compacting' => 'Compacting context…',
                  'complete' => 'Context compacted',
                  'failed' => 'Context compaction failed',
                  _ => 'Context compaction interrupted',
                },
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: MukaiColors.of(context).textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Second-level work grouping — mirrors the desktop `ProcessTranscript`.
//
// Consecutive work (reasoning, tool calls, and sub-bot delegations) collapses
// into one disclosure that describes what the model was doing, with the
// individual dropdowns nested inside it. Commentary or compaction breaks the
// run and stays flat in the transcript.
// ---------------------------------------------------------------------------

bool _isWork(ChatBlock block) => block is ToolBlock || block is SubBotBlock;

bool _isReasoning(ChatBlock block) =>
    block is ToolBlock && block.label == 'Reasoning';

bool _isToolPart(ChatBlock block) => _isWork(block) && !_isReasoning(block);

String? _mediaKind(ChatBlock block) =>
    block is ToolBlock && block.previewHref != null ? 'image' : null;

List<Object> _workRuns(List<ChatBlock> blocks) {
  final runs = <Object>[];
  for (final block in blocks) {
    if (!_isWork(block)) {
      runs.add(block);
      continue;
    }
    final last = runs.isEmpty ? null : runs.last;
    final group = last is List<ChatBlock> ? last : null;
    final firstTool = group
        ?.where(_isToolPart)
        .firstOrNull;
    final joins =
        group != null &&
        (_isReasoning(block) ||
            firstTool == null ||
            _mediaKind(block) == _mediaKind(firstTool));
    if (joins) {
      group.add(block);
    } else {
      runs.add(<ChatBlock>[block]);
    }
  }
  return runs;
}

const _groupCompletedLabels = <String, String>{
  'Read a file': 'Read files',
  'Wrote a file': 'Wrote files',
  'Updated a file': 'Updated files',
  'Created a folder': 'Created folders',
  'Searched files': 'Searched files',
  'Sent an update': 'Sent updates',
  'Received your decision': 'Reviewed requests',
  'Received your answer': 'Reviewed requests',
  'Viewed an image': 'Viewed images',
  'Ran a command': 'Ran commands',
  'Searched the web': 'Searched the web',
  'Activity': 'Used tools',
};

String _workGroupLabel(List<ChatBlock> group, bool active) {
  final tools = group.where(_isToolPart).toList();
  if (tools.isEmpty) return active ? 'Thinking' : 'Reasoned';
  final media = _mediaKind(tools.first);
  if (media != null && tools.every((tool) => _mediaKind(tool) == media)) {
    final count = active
        ? tools.length
        : tools.where((tool) => tool is ToolBlock && tool.state == ToolState.done).length;
    if (count == 0) return 'Image viewing';
    return '${active ? 'Viewing' : 'Viewed'} $count image${count == 1 ? '' : 's'}';
  }
  if (active) {
    final running = group
        .whereType<ToolBlock>()
        .where((tool) => tool.state == ToolState.running)
        .toList();
    final latest = running.isNotEmpty ? running.last : group.last;
    return latest is ToolBlock ? latest.label : 'Delegating to a bot';
  }
  final labels = <String>{};
  for (final tool in tools) {
    labels.add(switch (tool) {
      final ToolBlock b => _groupCompletedLabels[b.label] ?? b.label,
      SubBotBlock() => 'Delegated to bots',
      _ => 'Used tools',
    });
  }
  final ordered = labels.toList();
  return ordered
      .asMap()
      .entries
      .map(
        (entry) =>
            entry.key == 0
            ? entry.value
            : entry.value[0].toLowerCase() + entry.value.substring(1),
      )
      .join(', ');
}

/// The middle dropdown: one label for everything the model did between
/// commentary breaks, wrapping the individual tool disclosures inside.
class _WorkGroupDisclosure extends StatelessWidget {
  const _WorkGroupDisclosure({
    super.key,
    required this.group,
    required this.active,
    required this.bots,
  });

  final List<ChatBlock> group;
  final bool active;
  final List<MukaiBot> bots;

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textMuted);
    final problems = group
        .whereType<ToolBlock>()
        .where((tool) => tool.state == ToolState.error)
        .length;
    final tools = group.where(_isToolPart).toList();
    final media =
        tools.isNotEmpty &&
        _mediaKind(tools.first) != null &&
        tools.every((tool) => _mediaKind(tool) == _mediaKind(tools.first));
    final icon = problems > 0
        ? Icons.error_outline_rounded
        : tools.isEmpty
        ? Icons.psychology_outlined
        : media
        ? Icons.image_outlined
        : Icons.description_outlined;
    return MukaiDisclosure(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: problems > 0
                ? Theme.of(context).colorScheme.error
                : colors.textMuted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _workGroupLabel(group, active),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (problems > 0) ...[
            const SizedBox(width: 6),
            Text('· $problems unsuccessful', style: style),
          ],
        ],
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 6),
        child: _BlockStack(blocks: group, bots: bots),
      ),
    );
  }
}

/// Renders the work transcript as flat commentary separated by collapsible
/// runs of tool activity, matching the desktop hierarchy:
/// `Worked for …` → what the model described doing → individual tool.
class _WorkTranscriptContent extends StatelessWidget {
  const _WorkTranscriptContent({
    required this.blocks,
    required this.bots,
    required this.continuing,
  });

  final List<ChatBlock> blocks;
  final List<MukaiBot> bots;
  final bool continuing;

  @override
  Widget build(BuildContext context) {
    final runs = _workRuns(blocks);
    final groupCount = runs.whereType<List<ChatBlock>>().length;
    final children = <Widget>[];
    var groupIndex = 0;
    for (var index = 0; index < runs.length; index++) {
      if (index > 0) children.add(const SizedBox(height: MukaiSpace.sm));
      final run = runs[index];
      if (run is List<ChatBlock>) {
        final running = run.whereType<ToolBlock>().any(
          (tool) => tool.state == ToolState.running,
        );
        children.add(
          _WorkGroupDisclosure(
            key: ValueKey('work-group-$index-${run.first.stableId ?? ''}'),
            group: run,
            active: continuing && (groupIndex == groupCount - 1 || running),
            bots: bots,
          ),
        );
        groupIndex++;
      } else {
        final block = run as ChatBlock;
        children.add(
          ChatBlockView(
            key: ValueKey('work-run-$index-${block.stableId ?? ''}'),
            block: block,
            bots: bots,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Lays blocks out with the app's rhythm: tighter inside a group, roomier
/// between a paragraph and the card that follows it.
class _BlockStack extends StatelessWidget {
  const _BlockStack({
    required this.blocks,
    required this.bots,
    this.onApproval,
  });

  final List<ChatBlock> blocks;
  final List<MukaiBot> bots;
  final void Function(ApprovalBlock approval, bool approved)? onApproval;

  double _gapBefore(ChatBlock? previous, ChatBlock current) {
    if (previous == null) return 0;
    bool cardLike(ChatBlock block) =>
        block is ChartBlock ||
        block is TableBlock ||
        block is ApprovalBlock ||
        block is SubBotBlock ||
        block is LinkBlock;
    if (cardLike(current) || cardLike(previous)) return MukaiSpace.md;
    if (current is HeadingBlock) return MukaiSpace.md;
    return MukaiSpace.sm;
  }

  @override
  Widget build(BuildContext context) {
    ChatBlock? previous;
    final List<Widget> children = <Widget>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      // Pending requests live in the composer dock, never twice in the thread.
      if (block is ApprovalBlock) continue;
      final double gap = _gapBefore(previous, block);
      if (gap > 0) children.add(SizedBox(height: gap));
      children.add(
        ChatBlockView(
          key: ValueKey(
            block.stableId?.isNotEmpty == true
                ? '${block.runtimeType}-${block.stableId}'
                : '${block.runtimeType}-$index',
          ),
          block: block,
          bots: bots,
          onApproval: onApproval,
        ),
      );
      previous = block;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
