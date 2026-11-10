import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/app/sidebar_canvas.dart';
import 'package:mukai_flutter/design/glass.dart';
import 'package:mukai_flutter/design/appearance.dart';
import 'package:mukai_flutter/design/theme.dart';
import 'package:mukai_flutter/design/widgets.dart';

void main() {
  testWidgets('AppBar glass remains a fixed circle with an inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: mukaiTheme(const MukaiPreferences(), Brightness.light),
        home: Scaffold(
          appBar: AppBar(
            leading: const MukaiGlassBackButton(),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: MukaiGlassPill.circle(
                  diameter: 44,
                  padding: 0,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit pursuit')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final element in find.byType(MukaiGlassSurface).evaluate()) {
      expect(tester.getSize(find.byWidget(element.widget)), const Size(44, 44));
      expect(
        tester.getTopLeft(find.byWidget(element.widget)).dx,
        greaterThan(0),
      );
    }
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Edit pursuit'), findsOneWidget);
  });

  testWidgets('glass returns after the sheet exits and fades in', (
    tester,
  ) async {
    final material = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: mukaiTheme(const MukaiPreferences(), Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                MukaiGlassVisibility(
                  child: SizedBox(key: material, width: 44, height: 44),
                ),
                TextButton(
                  onPressed: () => showMukaiSheet<void>(
                    context: context,
                    builder: (context) => SizedBox(
                      height: 300,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Dismiss sheet'),
                      ),
                    ),
                  ),
                  child: const Text('Open sheet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final opacity = find.ancestor(
      of: find.byKey(material),
      matching: find.byType(FadeTransition),
    );
    double alpha() => tester.widget<FadeTransition>(opacity).opacity.value;
    final original = material.currentContext;
    expect(alpha(), 1);
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(alpha(), 0);
    await tester.tap(find.text('Dismiss sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // The background route is current again, but the sheet is still exiting.
    expect(find.text('Dismiss sheet'), findsOneWidget);
    expect(alpha(), 0);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Dismiss sheet'), findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(alpha(), greaterThan(0));
    expect(alpha(), lessThan(1));
    await tester.pumpAndSettle();
    expect(alpha(), 1);
    expect(material.currentContext, same(original));
  });

  testWidgets('sidebar preserves the page state through open, close and drag', (
    tester,
  ) async {
    final canvas = GlobalKey<SidebarCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: mukaiTheme(const MukaiPreferences(), Brightness.light),
        home: SidebarCanvas(
          key: canvas,
          sidebar: const SizedBox.expand(),
          child: const _Page(),
        ),
      ),
    );
    final original = tester.state<_PageState>(find.byType(_Page));
    canvas.currentState!.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.state<_PageState>(find.byType(_Page)), same(original));
    await tester.pumpAndSettle();
    canvas.currentState!.close();
    await tester.pumpAndSettle();
    expect(tester.state<_PageState>(find.byType(_Page)), same(original));
    await tester.dragFrom(const Offset(10, 200), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(tester.state<_PageState>(find.byType(_Page)), same(original));
    expect(original.disposed, isFalse);
  });
}

class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Page'));
}
