import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/design/widgets.dart';

void main() {
  testWidgets('glass menu dims the background while open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: mukaiTheme(MukaiPreferences.defaults, Brightness.dark),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MukaiGlassMenuButton(
              tooltip: 'pick',
              up: true,
              icon: Icon(Icons.expand_more_rounded),
              items: [MukaiGlassMenuItem(label: 'A')],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();

    final dim = Colors.black.withValues(alpha: .38);
    final scrim = tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .where((b) => b.color == dim);
    expect(scrim.length, 1, reason: 'the glass menu should show a dim scrim');

    // Tap outside dismisses, and the scrim leaves with the route.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .where((b) => b.color == dim),
      isEmpty,
    );
  });
}
