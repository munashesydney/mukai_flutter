/// Formatting helpers shared across features. Pure functions, unit tested.
library;

import 'workspace_time.dart';

abstract final class Format {
  static String? workDuration(DateTime? started, DateTime? finished) {
    if (started == null || finished == null) return null;
    final elapsed = finished.difference(started);
    if (elapsed.isNegative) return null;
    final seconds = elapsed.inSeconds;
    if (seconds >= 3600) {
      return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m ${seconds % 60}s';
    }
    if (seconds >= 60) return '${seconds ~/ 60}m ${seconds % 60}s';
    return '${seconds}s';
  }

  /// "now", "4m", "5h", "2d", "1w" — the sidebar's compact relative time.
  static String relativeTime(DateTime time, {DateTime? now}) {
    final Duration diff = (now ?? DateTime.now()).difference(time);
    if (diff.isNegative) return 'now';
    if (diff.inSeconds < 45) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${diff.inDays ~/ 7}w';
  }

  /// Clock time for message rows, e.g. "14:32".
  static String clock(DateTime time, {String? timeZone}) {
    time = WorkspaceTime.local(time, timeZone);
    final String h = time.hour.toString().padLeft(2, '0');
    final String m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Middle-truncates long file names the way the desktop app does:
  /// `18baf1d6-c646-4d7c-a655-bb…3f1.webp`.
  static String compactFileName(String name, {int max = 34}) {
    if (name.length <= max) return name;
    final int dot = name.lastIndexOf('.');
    final String extension = (dot > 0 && name.length - dot <= 6)
        ? name.substring(dot)
        : '';
    final int keepEnd = extension.isEmpty ? 4 : extension.length + 2;
    final int head = (max - keepEnd - 1).clamp(8, name.length).toInt();
    return '${name.substring(0, head)}…${name.substring(name.length - keepEnd)}';
  }

  /// Clips a composer transcript preview to one tidy line.
  static String snippet(String text, {int max = 64}) {
    final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max - 1)}…';
  }

  /// Signs a diff count the way the Changes list shows it: `+2 -1`.
  static String diffSummary(int added, int removed) => '+$added -$removed';
}
