import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/api/api_repository.dart' show object, objects, string;
import '../../../design/appearance.dart';

/// Queue and memory-recovery status from the same scheduler snapshot as desktop.
class AIQueueNotice extends StatefulWidget {
  const AIQueueNotice({
    super.key,
    required this.activity,
    required this.conversationId,
  });
  final Map<String, dynamic> activity;
  final String conversationId;
  @override
  State<AIQueueNotice> createState() => _AIQueueNoticeState();
}

class _AIQueueNoticeState extends State<AIQueueNotice> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(covariant AIQueueNotice old) {
    super.didUpdateWidget(old);
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    if (objects(widget.activity['queued']).any(
      (w) =>
          w['conversationId'] == widget.conversationId &&
          object(w['memoryPressure'])['cooldownUntil'] != null,
    )) {
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
    final queued = objects(widget.activity['queued']);
    final pursuits = objects(widget.activity['pursuitQueued']);
    final index = queued.indexWhere(
      (w) => w['conversationId'] == widget.conversationId,
    );
    final pursuitIndex = pursuits.indexWhere(
      (w) => w['conversationId'] == widget.conversationId,
    );
    final active = objects(widget.activity['running'])
        .where(
          (w) =>
              w['conversationId'] == widget.conversationId &&
              w['memoryRetry'] is Map,
        )
        .firstOrNull;
    if (index < 0 && pursuitIndex < 0 && active == null) {
      return const SizedBox.shrink();
    }
    final work = index >= 0
        ? queued[index]
        : active ??
              (pursuitIndex >= 0
                  ? pursuits[pursuitIndex]
                  : <String, dynamic>{});
    final pressure = object(work['memoryPressure']),
        retry = object(work['memoryRetry']);
    final until = DateTime.tryParse(string(pressure['cooldownUntil']));
    final seconds = until == null
        ? 0
        : (until.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(
            0,
            36000,
          );
    final title = active != null
        ? retry['phase'] == 'compaction'
              ? 'Trying a smaller context'
              : 'Retrying after memory rejection'
        : pressure.isNotEmpty
        ? 'Waiting for memory recovery'
        : index >= 0
        ? 'Queued'
        : 'Pursuit queued';
    final detail = pressure.isNotEmpty || retry.isNotEmpty
        ? '${seconds > 0
              ? 'Retry in ${seconds}s'
              : index >= 0
              ? 'Waiting for a slot'
              : retry['phase'] == 'compaction'
              ? 'Saved progress preserved'
              : 'Recovery in progress'}${retry.isNotEmpty && retry['phase'] != 'compaction' ? ' · Retry ${retry['attempt']}/${retry['maxAttempts']}' : ''}'
        : '#${(index >= 0 ? index : pursuitIndex) + 1} in queue · Resumes automatically';
    final colors = MukaiColors.of(context), text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.accentSoft.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, size: 17, color: colors.accentInk),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.labelMedium),
                    const SizedBox(height: 3),
                    Text(detail, style: text.bodySmall),
                    if (pressure.isNotEmpty)
                      Text(
                        '${string(pressure['providerName'])} temporarily allows ${pressure['effectiveLimit']} AI requests; your saved maximum is ${pressure['configuredLimit']}.',
                        style: text.bodySmall,
                      ),
                    if (active != null)
                      Text(
                        'Continuing from saved results.',
                        style: text.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
