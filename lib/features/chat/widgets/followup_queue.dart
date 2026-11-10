import 'package:flutter/material.dart';
import '../../../app/scope.dart';
import '../../../core/message_reference.dart';
import '../../../design/appearance.dart';
import 'reference_preview.dart';
import 'open_content.dart';

class FollowupQueue extends StatelessWidget {
  const FollowupQueue({super.key, this.runActive = false});
  final bool runActive;

  Future<void> _edit(BuildContext context, Map<String, dynamic> item) async {
    final session = MukaiScope.sessionOf(context);
    final message = splitMessageReference(item['text'] as String? ?? '');
    final input = TextEditingController(text: message.text);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final busy = session.pendingFollowupActions.contains(item['id']);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.reference case final reference?)
                        ReferencePreview(reference: reference),
                      TextField(
                        controller: input,
                        autofocus: true,
                        minLines: 2,
                        maxLines: 5,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Edit queued message',
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final text = input.text.trim();
                                    if (text.isEmpty &&
                                        (item['attachments'] as List? ?? [])
                                            .isEmpty) {
                                      return;
                                    }
                                    final saved = await session.updateFollowup(
                                      item['id'] as String,
                                      'edit',
                                      text:
                                          message.reference?.format(text) ??
                                          text,
                                    );
                                    if (context.mounted && saved) {
                                      Navigator.pop(context);
                                    }
                                  },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                      if (session.error case final error?) Text(error),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      input.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    final active = session.activeReply;
    final colors = MukaiColors.of(context);
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: compact ? 110 : 230),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final item in session.followups)
            Builder(
              builder: (context) {
                final id = item['id'] as String;
                final pending = item['state'] == 'steering';
                final queued = item['state'] == 'queued';
                final busy = session.pendingFollowupActions.contains(id);
                final message = splitMessageReference(
                  item['text'] as String? ?? '',
                );
                final canSteer =
                    active != null &&
                    (item['botId'] == null || item['botId'] == active.botId);
                final idle = !session.responding && !runActive;
                return Container(
                  key: ValueKey('followup-$id'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.cardMuted,
                    border: Border.all(color: colors.hairline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!compact && message.reference != null)
                        ReferencePreview(reference: message.reference!),
                      Text(
                        message.text,
                        maxLines: compact ? 1 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      for (final file
                          in (compact
                              ? []
                              : item['attachments'] as List? ?? []))
                        TextButton.icon(
                          onPressed: () => openChatContent(
                            context,
                            'mukai-attachment:${file['id']}',
                            name: file['name'] as String? ?? 'File',
                          ),
                          icon: const Icon(Icons.attach_file_rounded, size: 15),
                          label: Text(file['name'] as String? ?? 'File'),
                        ),
                      if (pending)
                        const Text(
                          'Pending steering · applies at the next safe step',
                        ),
                      if (item['error'] case final String error) Text(error),
                      if (!queued && !pending) const Text('Sending…'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (queued) ...[
                            TextButton.icon(
                              onPressed: busy || (!canSteer && !idle)
                                  ? null
                                  : () => session.updateFollowup(
                                      id,
                                      canSteer ? 'steer' : 'send',
                                    ),
                              icon: Icon(
                                canSteer || !idle
                                    ? Icons.subdirectory_arrow_right_rounded
                                    : Icons.send_rounded,
                                size: 16,
                              ),
                              label: Text(canSteer || !idle ? 'Steer' : 'Send'),
                            ),
                            IconButton(
                              tooltip: 'Edit queued message',
                              onPressed: busy
                                  ? null
                                  : () => _edit(context, item),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                          ],
                          if (queued || pending)
                            IconButton(
                              tooltip: pending
                                  ? 'Cancel pending steering'
                                  : 'Remove follow-up',
                              onPressed: busy
                                  ? null
                                  : () => session.updateFollowup(id, 'delete'),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
