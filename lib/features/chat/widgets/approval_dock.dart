import 'package:flutter/material.dart';

import '../../../app/scope.dart';
import '../../../design/appearance.dart';
import '../../../design/widgets.dart';
import '../../../domain/models.dart';

/// Human requests temporarily occupy the composer. The thread remains readable
/// and the session keeps its draft and attachments until the requests resolve.
class ApprovalDock extends StatefulWidget {
  const ApprovalDock({super.key, required this.requests});
  final List<ApprovalBlock> requests;
  @override
  State<ApprovalDock> createState() => _ApprovalDockState();
}

class _ApprovalDockState extends State<ApprovalDock> {
  String? _selected, _busy, _error, _denying;
  final Map<String, String> _denialDrafts = {};
  final Map<String, String> _drafts = {};
  String _id(ApprovalBlock request) =>
      request.id ?? 'demo-${request.toolName}-${request.reason}';

  Future<void> _answer(
    ApprovalBlock request, {
    bool? approved,
    String? answer,
    String? reason,
  }) async {
    if (_busy != null || (answer != null && answer.trim().isEmpty)) return;
    setState(() {
      _busy = _id(request);
      _error = null;
    });
    try {
      final session = MukaiScope.sessionOf(context);
      if (approved != null) {
        await session.resolveApproval(
          request,
          approved: approved,
          reason: reason,
        );
      } else {
        await session.answerApproval(request, answer!.trim());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests;
    if (requests.isEmpty) return const SizedBox.shrink();
    final selectedIndex = requests.indexWhere((r) => _id(r) == _selected);
    final index = selectedIndex < 0 ? 0 : selectedIndex;
    final request = requests[index];
    final id = _id(request);
    final clarification = request.ask?['action'] == 'clarification';
    final colors = MukaiColors.of(context), text = Theme.of(context).textTheme;
    final busy = _busy != null;
    final denying = _denying == id && !clarification;
    return Padding(
      key: const ValueKey('approval-dock'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.hairlineStrong),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                ((MediaQuery.sizeOf(context).height -
                            MediaQuery.viewInsetsOf(context).bottom -
                            MediaQuery.paddingOf(context).vertical -
                            100) *
                        .75)
                    .clamp(140, 380),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    clarification
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.verified_user_outlined,
                    size: 17,
                    color: colors.accentInk,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clarification ? 'A question for you' : 'Approval needed',
                      style: text.titleSmall,
                    ),
                  ),
                  if (requests.length > 1) ...[
                    IconButton(
                      tooltip: 'Previous request',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy || index == 0
                          ? null
                          : () => setState(
                              () => _selected = _id(requests[index - 1]),
                            ),
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    ),
                    Text(
                      '${index + 1}/${requests.length}',
                      style: text.labelSmall,
                    ),
                    IconButton(
                      tooltip: 'Next request',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy || index == requests.length - 1
                          ? null
                          : () => setState(
                              () => _selected = _id(requests[index + 1]),
                            ),
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  key: PageStorageKey('approval-details-$id'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (request.ask == null) ...[
                        Text(
                          '${request.botName?.isNotEmpty == true ? request.botName : 'Your companion'} wants to use ${request.toolName}.',
                          style: text.bodySmall,
                        ),
                        const SizedBox(height: 8),
                      ],
                      SelectableText(
                        request.reason,
                        style: text.bodyMedium?.copyWith(height: 1.5),
                      ),
                      if (request.notice?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(request.notice!, style: text.bodySmall),
                        ),
                      if (clarification) ...[
                        const SizedBox(height: 12),
                        for (final option
                            in (request.ask?['options'] as List? ?? [])
                                .whereType<Map>())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MukaiButton(
                              label: option['label']?.toString() ?? '',
                              expand: true,
                              variant: MukaiButtonVariant.quiet,
                              onPressed: busy
                                  ? null
                                  : () => _answer(
                                      request,
                                      answer: option['label']?.toString(),
                                    ),
                            ),
                          ),
                        TextFormField(
                          key: ValueKey('approval-answer-$id'),
                          initialValue: _drafts[id] ?? '',
                          enabled: !busy,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Your answer',
                          ),
                          onChanged: (value) =>
                              setState(() => _drafts[id] = value),
                        ),
                      ],
                      if (denying) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          key: ValueKey('denial-reason-$id'),
                          initialValue: _denialDrafts[id] ?? '',
                          autofocus: true,
                          enabled: !busy,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 16000,
                          decoration: const InputDecoration(
                            labelText: 'Reason for denial',
                            hintText: 'Explain what should change…',
                          ),
                          onChanged: (value) =>
                              setState(() => _denialDrafts[id] = value),
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _error!,
                            style: text.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (clarification)
                Row(
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _answer(
                              request,
                              answer:
                                  'I’m skipping this question. Please proceed without an answer.',
                            ),
                      child: const Text('Skip'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MukaiButton(
                        label: 'Send answer',
                        expand: true,
                        compact: true,
                        busy: busy,
                        onPressed: busy || (_drafts[id]?.trim().isEmpty ?? true)
                            ? null
                            : () => _answer(request, answer: _drafts[id] ?? ''),
                      ),
                    ),
                  ],
                )
              else if (denying)
                Row(
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => _denying = null),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MukaiButton(
                        label: 'Send denial',
                        compact: true,
                        expand: true,
                        busy: busy,
                        onPressed:
                            busy || (_denialDrafts[id]?.trim().isEmpty ?? true)
                            ? null
                            : () => _answer(
                                request,
                                approved: false,
                                reason: _denialDrafts[id]!.trim(),
                              ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: MukaiButton(
                        key: const ValueKey('approval-approve'),
                        label: 'Approve',
                        compact: true,
                        expand: true,
                        busy: busy,
                        onPressed: busy
                            ? null
                            : () => _answer(request, approved: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MukaiButton(
                        label: 'Decline',
                        compact: true,
                        expand: true,
                        variant: MukaiButtonVariant.quiet,
                        onPressed: busy
                            ? null
                            : () => _answer(request, approved: false),
                      ),
                    ),
                  ],
                ),
              if (!clarification && !denying)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _denying = id),
                    child: const Text('Deny with reason'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
