import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mukai_flutter/core/format.dart';
import 'package:mukai_flutter/core/workspace_time.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/features/settings/timezone_screen.dart';

void main() {
  testWidgets(
    'timezone search fits a small screen with large text and the keyboard open',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
          home: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.7),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: TimezoneScreen(
              workspace: MukaiWorkspace(
                name: 'A travelling workspace',
                tagline: '',
                kind: 'Folder workspace',
                timeZone: 'America/Vancouver',
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Kathmandu');
      await tester.pump();
      await tester.ensureVisible(find.text('Asia/Kathmandu'));
      await tester.tap(find.text('Asia/Kathmandu'));
      await tester.pump();
      expect(find.textContaining('UTC+05:45'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'renders one instant in each workspace without changing its UTC value',
    () {
      final instant = DateTime.parse('2025-01-16T07:30:00Z');
      expect(Format.clock(instant, timeZone: 'America/Vancouver'), '23:30');
      expect(Format.clock(instant, timeZone: 'Asia/Kathmandu'), '13:15');
      expect(Format.clock(instant, timeZone: 'UTC'), '07:30');
      expect(WorkspaceTime.local(instant, 'America/Vancouver').day, 15);
      expect(instant.toIso8601String(), '2025-01-16T07:30:00.000Z');
      expect(
        WorkspaceTime.local(instant, 'Asia/Kathmandu').millisecondsSinceEpoch,
        instant.millisecondsSinceEpoch,
      );
      expect(WorkspaceTime.offset(instant, 'Asia/Kathmandu'), 'UTC+05:45');
    },
  );

  test(
    'uses current Vancouver rules and handles historical DST gaps and repeats',
    () {
      expect(
        Format.clock(
          DateTime.parse('2026-11-05T02:00:00Z'),
          timeZone: 'America/Vancouver',
        ),
        '19:00',
      );
      expect(
        Format.clock(
          DateTime.parse('2025-03-09T09:59:00Z'),
          timeZone: 'America/Vancouver',
        ),
        '01:59',
      );
      expect(
        Format.clock(
          DateTime.parse('2025-03-09T10:00:00Z'),
          timeZone: 'America/Vancouver',
        ),
        '03:00',
      );
      final first = WorkspaceTime.local(
        DateTime.parse('2025-11-02T08:30:00Z'),
        'America/Vancouver',
      );
      final second = WorkspaceTime.local(
        DateTime.parse('2025-11-02T09:30:00Z'),
        'America/Vancouver',
      );
      expect(first.hour, second.hour);
      expect(first.timeZoneOffset, const Duration(hours: -7));
      expect(second.timeZoneOffset, const Duration(hours: -8));
      expect(second.difference(first), const Duration(hours: 1));
    },
  );

  test(
    'calendar labels compare local dates across midnight and short or long days',
    () {
      expect(
        WorkspaceTime.dayDifference(
          DateTime.parse('2025-03-10T07:00:00Z'),
          DateTime.parse('2025-03-09T08:00:00Z'),
          'America/Vancouver',
        ),
        1,
      );
      expect(
        WorkspaceTime.dayDifference(
          DateTime.parse('2025-11-03T07:30:00Z'),
          DateTime.parse('2025-11-02T07:00:00Z'),
          'America/Vancouver',
        ),
        0,
      );
      expect(
        WorkspaceTime.dayDifference(
          DateTime.parse('2025-01-16T07:30:00Z'),
          DateTime.parse('2025-01-16T08:30:00Z'),
          'America/Vancouver',
        ),
        -1,
      );
    },
  );

  test(
    'supports aliases, rejects ambiguous zones, and preserves legacy behavior',
    () {
      for (final zone in [
        'UTC',
        'America/Vancouver',
        'Asia/Kathmandu',
        'US/Pacific',
      ]) {
        expect(WorkspaceTime.isValid(zone), isTrue);
      }
      for (final zone in ['PST', '-08:00', 'Mars/Olympus', '']) {
        expect(WorkspaceTime.isValid(zone), isFalse);
      }
      final instant = DateTime.parse('2026-11-05T02:00:00Z');
      expect(WorkspaceTime.local(instant, null), instant.toLocal());
      expect(WorkspaceTime.local(instant, 'Mars/Olympus'), instant);
    },
  );
}
