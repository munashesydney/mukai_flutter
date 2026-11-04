/// Readable, redacted tool parameters, matching the desktop approval details.
String approvalDetails(dynamic input, [Map<String, dynamic>? presentation]) {
  final sensitive = RegExp(
    r'password|secret|token|api[_-]?key|authorization|credential',
    caseSensitive: false,
  );
  String label(String key) {
    final value = key
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAll(RegExp(r'[_-]+'), ' ');
    return value.isEmpty
        ? ''
        : '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String readable(dynamic value, [int depth = 0]) {
    if (value == null) return 'None';
    if (depth > 16) return 'Nested details';
    if (value is List) {
      return value.isEmpty
          ? 'None'
          : value.map((v) => '• ${readable(v, depth + 1)}').join('\n');
    }
    if (value is Map) {
      return value.entries
          .map(
            (e) =>
                '${label(e.key.toString())}: ${sensitive.hasMatch(e.key.toString()) ? '[redacted]' : readable(e.value, depth + 1)}',
          )
          .join('\n');
    }
    return value.toString();
  }

  if (input is! Map) return readable(input);
  final fields = presentation?['fields'] is List
      ? presentation!['fields'] as List
      : input.keys.map((key) => {'parameter': key}).toList();
  final blocks = <String>[];
  final title = presentation?['title'];
  if (title is String && title.trim().isNotEmpty) blocks.add(title.trim());
  for (final field in fields.whereType<Map>()) {
    final parameter = field['parameter']?.toString() ?? '';
    if (!input.containsKey(parameter)) continue;
    final heading = field['label']?.toString() ?? label(parameter);
    final value =
        sensitive.hasMatch(parameter) || field['presentation'] == 'secret'
        ? '[redacted]'
        : readable(input[parameter]);
    blocks.add('$heading: $value');
  }
  return blocks.isEmpty ? 'No parameters.' : blocks.join('\n\n');
}
