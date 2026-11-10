class MessageReference {
  const MessageReference({required this.label, required this.text});
  final String label, text;

  String format(String instruction) =>
      'Regarding $label:\n${text.split('\n').map((line) => '> $line').join('\n')}\n\n$instruction';
}

({String text, MessageReference? reference}) splitMessageReference(
  String text,
) {
  if (!text.startsWith('Regarding ')) return (text: text, reference: null);
  final start = text.indexOf(':\n> ', 'Regarding '.length);
  if (start < 0) return (text: text, reference: null);
  final end = text.indexOf('\n\n', start + 2);
  if (end < 0) return (text: text, reference: null);
  final lines = text.substring(start + 2, end).split('\n');
  if (!lines.every((line) => line.startsWith('> '))) {
    return (text: text, reference: null);
  }
  return (
    text: text.substring(end + 2),
    reference: MessageReference(
      label: text.substring('Regarding '.length, start),
      text: lines.map((line) => line.substring(2)).join('\n'),
    ),
  );
}
