import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

/// Calendar presentation only. Domain timestamps and elapsed durations stay instants.
abstract final class WorkspaceTime {
  static bool _ready = false;

  static void _initialize() {
    if (_ready) return;
    data.initializeTimeZones();
    _ready = true;
  }

  static tz.Location? location(String? name) {
    if (name == null || name.isEmpty) return null;
    _initialize();
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  static bool isValid(String name) =>
      (name == 'UTC' || name.contains('/')) && location(name) != null;

  static List<String> get names {
    _initialize();
    return {
      'UTC',
      ...tz.timeZoneDatabase.locations.keys,
    }.where((name) => name == 'UTC' || name.contains('/')).toList()..sort();
  }

  static DateTime local(DateTime instant, String? timeZone) {
    // Older servers have no workspace preference; retain their device-time behavior.
    if (timeZone == null || timeZone.isEmpty) return instant.toLocal();
    final zone = location(timeZone);
    return zone == null ? instant.toUtc() : tz.TZDateTime.from(instant, zone);
  }

  /// Compare calendar days, not 24-hour durations across daylight-saving boundaries.
  static int dayDifference(DateTime instant, DateTime now, String? timeZone) {
    final date = local(instant, timeZone);
    final today = local(now, timeZone);
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  }

  static String offset(DateTime instant, String name) {
    final minutes = local(instant, name).timeZoneOffset.inMinutes;
    final absolute = minutes.abs();
    return 'UTC${minutes < 0 ? '−' : '+'}${(absolute ~/ 60).toString().padLeft(2, '0')}:${(absolute % 60).toString().padLeft(2, '0')}';
  }

  static String city(String name) => name.split('/').last.replaceAll('_', ' ');
}
