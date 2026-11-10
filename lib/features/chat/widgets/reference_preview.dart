import 'package:flutter/material.dart';
import '../../../core/message_reference.dart';
import '../../../design/appearance.dart';
import '../../../app/scope.dart';

Widget referenceSelectionMenu(
  BuildContext context,
  EditableTextState editable, {
  String? label,
}) {
  final value = editable.textEditingValue;
  final selected = value.selection.textInside(value.text);
  final session = MukaiScope.sessionOf(context);
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editable.contextMenuAnchors,
    buttonItems: [
      if (selected.trim().isNotEmpty &&
          !session.readOnly &&
          session.bot.id.isNotEmpty)
        ContextMenuButtonItem(
          label: 'Ask ${session.bot.name}',
          onPressed: () {
            session.setReference(
              MessageReference(
                label: label ?? session.bot.name,
                text: selected,
              ),
            );
            editable.hideToolbar();
          },
        ),
      ...editable.contextMenuButtonItems,
    ],
  );
}

class ReferencePreview extends StatelessWidget {
  const ReferencePreview({super.key, required this.reference, this.onRemove});
  final MessageReference reference;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.format_quote_rounded, size: 16),
            const SizedBox(width: 5),
            const Text('Selection'),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                reference.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted),
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove reference',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 16),
                visualDensity: VisualDensity.compact,
              )
            else
              const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          reference.text,
          maxLines: onRemove == null ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.cardMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onRemove != null
              ? null
              : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .65,
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(reference.text),
                        ),
                      ),
                    ),
                  ),
                ),
          child: Padding(padding: const EdgeInsets.all(10), child: content),
        ),
      ),
    );
  }
}
