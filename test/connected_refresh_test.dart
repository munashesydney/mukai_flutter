import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/features/connected/connected_widgets.dart';

void main() {
  testWidgets(
    'background refresh preserves layout, drafts, and scroll position',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var pending = Completer<dynamic>();
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
          home: Scaffold(
            body: ConnectedAsync(
              refreshInterval: const Duration(seconds: 5),
              load: () => pending.future,
              builder: (context, data, reload) {
                builds++;
                return Column(
                  children: [
                    Text('Version ${data['version']}'),
                    const TextField(),
                    Expanded(
                      child: ListView(
                        controller: scroll,
                        children: List.generate(
                          40,
                          (i) => ListTile(title: Text('Item $i')),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete({
        'version': 1,
        'items': [1, 2],
      });
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      final position = tester.getTopLeft(find.byType(TextField));
      final offset = scroll.offset;
      final before = builds;

      pending = Completer<dynamic>();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.getTopLeft(find.byType(TextField)), position);
      pending.complete({
        'version': 1,
        'items': [1, 2],
      });
      await tester.pump();
      await tester.pump();
      expect(builds, before);

      pending = Completer<dynamic>();
      await tester.pump(const Duration(seconds: 5));
      pending.complete({
        'version': 2,
        'items': [1, 2, 3],
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('Version 2'), findsOneWidget);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(scroll.offset, offset);
      expect(tester.getTopLeft(find.byType(TextField)), position);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background failures stay quiet while manual refresh reports errors',
    (tester) async {
      var pending = Completer<dynamic>();
      await tester.pumpWidget(
        MaterialApp(
          theme: mukaiTheme(MukaiPreferences.defaults, Brightness.light),
          home: Scaffold(
            body: ConnectedAsync(
              refreshInterval: const Duration(seconds: 5),
              load: () => pending.future,
              builder: (context, data, reload) => Column(
                children: [
                  Text(data['title'] as String),
                  TextButton(onPressed: reload, child: const Text('Refresh')),
                ],
              ),
            ),
          ),
        ),
      );
      pending.complete({'title': 'Saved content'});
      await tester.pump();
      await tester.pump();
      pending = Completer<dynamic>();
      await tester.pump(const Duration(seconds: 5));
      pending.completeError(Exception('Offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Saved content'), findsOneWidget);
      expect(find.textContaining('Offline'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      pending = Completer<dynamic>();
      await tester.tap(find.text('Refresh'));
      pending.completeError(Exception('Offline'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Offline'), findsOneWidget);
      pending = Completer<dynamic>();
      await tester.pump(const Duration(seconds: 5));
      pending.complete({'title': 'Saved content'});
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Offline'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
