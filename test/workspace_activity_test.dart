import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/home_shell.dart';
import 'package:mukai_flutter/app/scope.dart';
import 'package:mukai_flutter/data/demo/demo_repository.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/design/widgets.dart';
import 'package:mukai_flutter/domain/models.dart';
import 'package:mukai_flutter/features/home/widgets/workspace_sheet.dart';
import 'package:mukai_flutter/state/session_controller.dart';

const other = MukaiWorkspace(
  id: 'other',
  name: 'Other workspace',
  kind: 'Folder workspace',
  tagline: '',
);
const idle = MukaiWorkspace(
  id: 'idle',
  name: 'Idle workspace',
  kind: 'Personal workspace',
  tagline: '',
);

class _PickerSession extends SessionController {
  _PickerSession() : super(MukaiDemoRepository(latency: Duration.zero));
  @override
  List<MukaiWorkspace> get workspaces => [workspace, other, idle];
}

Future<void> frame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

void main() {
  test(
    'workspace activity includes other running workspaces and pursuits but not queued-only work',
    () async {
      final session = _PickerSession();
      addTearDown(session.dispose);
      session.aiActivity = {
        'workingWorkspaceIds': ['using-tools'],
        'running': [
          {'workspaceId': 'other', 'botId': 'remote-agent'},
          {'workspaceId': 'other', 'botId': 'another-agent'},
          {'kind': 'connection'},
        ],
        'pursuitRunning': [
          {'workspaceId': 'pursuit-workspace', 'botId': 'builder'},
        ],
        'queued': [
          {'workspaceId': 'idle', 'botId': 'waiting'},
        ],
        'pursuitQueued': [
          {'workspaceId': 'idle', 'botId': 'waiting'},
        ],
      };
      expect(session.workingWorkspaceIds, {
        'other',
        'pursuit-workspace',
        'using-tools',
      });
      await session.openBot('scout', conversationId: 'scout-today');
      await session.send('Keep working');
      expect(session.workingWorkspaceIds, {
        'other',
        'pursuit-workspace',
        'using-tools',
        session.workspace.id,
      });
      session.stop();
      expect(session.workingWorkspaceIds, {
        'other',
        'pursuit-workspace',
        'using-tools',
      });
      session.aiActivity = {};
      expect(session.workingWorkspaceIds, isEmpty);
    },
  );

  testWidgets(
    'pursuit activity spins the nav icon and shows dots only inside the picker',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _PickerSession();
      final appearance = AppearanceController();
      session.aiActivity = {
        'pursuitRunning': [
          {'workspaceId': session.workspace.id, 'botId': 'scout'},
          {'workspaceId': other.id, 'botId': 'remote-agent'},
        ],
      };
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        appearance.dispose();
      });
      await tester.pumpWidget(
        MukaiScope(
          session: session,
          appearance: appearance,
          child: MaterialApp(
            theme: mukaiTheme(appearance.preferences, Brightness.dark),
            home: const HomeShell(),
          ),
        ),
      );
      await frame(tester);
      expect(find.byType(BouncingDots), findsNothing);
      await tester.tap(find.byTooltip('Open sidebar'));
      await frame(tester);
      expect(find.byType(BouncingDots), findsNothing);
      final pursuits = find.widgetWithText(ListTile, 'Pursuits');
      final spinner = find.descendant(
        of: pursuits,
        matching: find.byType(CircularProgressIndicator),
      );
      final target = find.descendant(
        of: pursuits,
        matching: find.byIcon(Icons.track_changes_rounded),
      );
      expect(spinner, findsOneWidget);
      expect(target, findsNothing);
      await tester.tap(find.byTooltip('Switch workspace'));
      await frame(tester);
      Finder row(String id) => find.byKey(ValueKey('workspace-picker-$id'));
      Finder dots(String id) =>
          find.descendant(of: row(id), matching: find.byType(BouncingDots));
      expect(find.text('Your workspaces'), findsOneWidget);
      expect(dots(session.workspace.id), findsOneWidget);
      expect(dots(other.id), findsOneWidget);
      expect(dots(idle.id), findsNothing);
      expect(
        tester.widget<MukaiRow>(row(session.workspace.id)).selected,
        isTrue,
      );

      session.aiActivity = {
        'running': [
          {'workspaceId': idle.id, 'botId': 'new-agent'},
        ],
      };
      unawaited(session.loadRecents());
      await frame(tester);
      expect(dots(session.workspace.id), findsNothing);
      expect(dots(other.id), findsNothing);
      expect(dots(idle.id), findsOneWidget);
      expect(
        tester.widget<MukaiRow>(row(session.workspace.id)).selected,
        isTrue,
      );
      session.aiActivity = {};
      unawaited(session.loadRecents());
      await frame(tester);
      expect(find.byType(BouncingDots), findsNothing);
      expect(find.text('Your workspaces'), findsOneWidget);
      Navigator.of(tester.element(find.text('Your workspaces'))).pop();
      await frame(tester);
      expect(spinner, findsNothing);
      expect(target, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the reusable picker retains the selected check while showing working dots',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
          home: Scaffold(
            body: WorkspaceSheet(
              current: other,
              others: const [idle],
              workingWorkspaceIds: const {'other', 'idle'},
              onSelect: (_) {},
              onCreate: () {},
            ),
          ),
        ),
      );
      await frame(tester);
      expect(find.byType(BouncingDots), findsNWidgets(2));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
