import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/core/format.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 2, 14, 32);

  group('relativeTime', () {
    test('collapses anything very recent', () {
      expect(
        Format.relativeTime(
          now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        'now',
      );
      expect(
        Format.relativeTime(now.add(const Duration(minutes: 5)), now: now),
        'now',
      );
    });

    test('steps through minutes, hours, days and weeks', () {
      expect(
        Format.relativeTime(now.subtract(const Duration(minutes: 4)), now: now),
        '4m',
      );
      expect(
        Format.relativeTime(now.subtract(const Duration(hours: 5)), now: now),
        '5h',
      );
      expect(
        Format.relativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d',
      );
      expect(
        Format.relativeTime(now.subtract(const Duration(days: 14)), now: now),
        '2w',
      );
    });
  });

  group('clock', () {
    test('zero-pads both fields', () {
      expect(Format.clock(DateTime(2026, 3, 5, 9, 7)), '09:07');
      expect(Format.clock(DateTime(2026, 3, 5, 0, 0)), '00:00');
    });
  });

  group('compactFileName', () {
    test('leaves short names alone', () {
      expect(Format.compactFileName('project-notes.md'), 'project-notes.md');
    });

    test('middle-truncates long names and keeps the extension', () {
      const String uuid = '18baf1d6-c646-4d7c-a655-bb21f0c9e3f1.webp';
      final String compact = Format.compactFileName(uuid);
      expect(compact.length, 34);
      expect(compact, contains('…'));
      expect(compact, endsWith('.webp'));
      expect(compact, startsWith('18baf1d6'));
    });

    test('never returns something longer than the original', () {
      const String uuid = '18baf1d6-c646-4d7c-a655-bb21f0c9e3f1.webp';
      expect(
        Format.compactFileName(uuid).length,
        lessThanOrEqualTo(uuid.length),
      );
    });
  });

  group('snippet', () {
    test('flattens whitespace', () {
      expect(Format.snippet('two  lines\n\napart'), 'two lines apart');
    });

    test('clips to the limit with an ellipsis', () {
      final String long = 'x' * 200;
      final String clipped = Format.snippet(long, max: 20);
      expect(clipped.length, 20);
      expect(clipped, endsWith('…'));
    });
  });

  test('diffSummary signs each count', () {
    expect(Format.diffSummary(2, 1), '+2 -1');
    expect(Format.diffSummary(0, 0), '+0 -0');
  });
}
