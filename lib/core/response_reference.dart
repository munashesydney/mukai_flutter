/// Explicit file references accepted by the server, mirrored from Electron.
class ResponseReference {
  const ResponseReference(this.type, this.value, {this.line});
  final String type, value;
  final int? line;
}

ResponseReference? parseResponseReference(String href) {
  bool controls(String s) => s.runes.any((c) => c < 32 || c == 127);
  if (href.isEmpty || href.length > 4500 || controls(href)) return null;
  final match = RegExp(r'#L([1-9]\d{0,6})$').firstMatch(href);
  final line = match == null ? null : int.tryParse(match[1]!);
  final target = match == null ? href : href.substring(0, match.start);
  try {
    final internal = RegExp(
      r'^mukai://(artifact|attachment|file)/(.+)$',
      caseSensitive: false,
    ).firstMatch(target);
    if (internal != null) {
      final type = internal[1]!.toLowerCase(),
          value = Uri.decodeComponent(internal[2]!);
      if (controls(value) ||
          (type != 'file' &&
              !RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(value))) {
        return null;
      }
      return ResponseReference(type, value, line: line);
    }
    final legacy = RegExp(
      r'^mukai-(artifact|attachment):(.+)$',
    ).firstMatch(target);
    if (legacy != null) {
      final id = Uri.decodeComponent(legacy[2]!);
      return RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(id)
          ? ResponseReference(legacy[1]!, id, line: line)
          : null;
    }
    if (RegExp(
          r'^(?:[a-z][a-z0-9+.-]*:|//|\\\\|#)',
          caseSensitive: false,
        ).hasMatch(target) &&
        !RegExp(r'^[a-z]:[\\/]', caseSensitive: false).hasMatch(target)) {
      return null;
    }
    if (target.isEmpty || target.contains('?') || target.contains('#')) {
      return null;
    }
    final path = Uri.decodeComponent(target);
    return controls(path) ? null : ResponseReference('file', path, line: line);
  } catch (_) {
    return null;
  }
}
