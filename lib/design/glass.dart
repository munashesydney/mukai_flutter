/// Apple's iOS 26 liquid glass as a background material for Flutter controls.
///
/// The material itself is rendered natively (`UIGlassEffect` inside a
/// platform view, see `native/ios/AppDelegate.swift`) because no Flutter
/// primitive refracts like glass; the controls stay ordinary Flutter widgets
/// drawn on top. Wherever the native material is unavailable — Android, web,
/// or iOS below 26 — these widgets add literally nothing, so the fallback is
/// exactly the pre-glass UI.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import 'appearance.dart';

/// Capability probe for the native glass bridge, resolved once and cached.
abstract final class MukaiGlass {
  static const MethodChannel _channel = MethodChannel('com.mukai.mobile/glass');
  static Future<bool>? _probe;

  static Future<bool> get available => _probe ??= _detect();

  static final _coveredRoutes = ValueNotifier<Map<Route<dynamic>, int>>({});

  /// Keep background glass out of composition until the covering sheet's
  /// exit animation finishes, including when multiple sheets are stacked.
  static void coverRouteUntil(
    Route<dynamic>? owner,
    Future<dynamic> completed,
  ) {
    if (owner == null) return;
    final covers = Map<Route<dynamic>, int>.of(_coveredRoutes.value);
    covers[owner] = (covers[owner] ?? 0) + 1;
    _coveredRoutes.value = covers;
    completed.whenComplete(() {
      final remaining = Map<Route<dynamic>, int>.of(_coveredRoutes.value);
      final count = (remaining[owner] ?? 1) - 1;
      if (count == 0) {
        remaining.remove(owner);
      } else {
        remaining[owner] = count;
      }
      _coveredRoutes.value = remaining;
    });
  }

  static bool? _lastDark;

  /// Tells the native side the app's brightness. The app can force Light or
  /// Dark while the system sits in the other mode, and a platform view only
  /// sees the system appearance — without this the glass renders the wrong
  /// mode's material. Deduplicated: every surface calls it, the channel
  /// fires once per actual change.
  static void syncAppearance({required bool isDark}) {
    if (_lastDark == isDark) return;
    _lastDark = isDark;
    // Fire-and-forget; failures leave the glass on its last appearance.
    _channel
        .invokeMethod<void>('appearance', <String, Object?>{'dark': isDark})
        .catchError((Object _) {});
  }

  static Future<bool> _detect() async {
    if (kIsWeb || !Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Rebuilds [builder] with the glass capability once known, so callers whose
/// own fallback decoration changes with glass (the composer, for instance)
/// can adapt instead of being covered by the material.
class MukaiGlassProbe extends StatelessWidget {
  const MukaiGlassProbe({super.key, required this.builder, this.child});

  final Widget Function(BuildContext context, bool glass, Widget? child)
  builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: MukaiGlass.available,
      initialData: false,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) =>
          builder(context, snapshot.data == true, child),
    );
  }
}

/// Rounded-rect glass material behind [child] on iOS 26+; a transparent
/// passthrough everywhere else.
class MukaiGlassSurface extends StatelessWidget {
  const MukaiGlassSurface({
    super.key,
    required this.child,
    this.cornerRadius = 26,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double cornerRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // The glass must hug the controls it sits behind, so the content keeps
    // its natural size instead of expanding (a Center/Row wrapper either
    // stretched the pill across the header or starved a TextField of width).
    // Icon buttons report their fixed size; the composer's InputDecorator
    // still claims the full finite width it is given.
    final Widget content = Padding(padding: padding, child: child);
    return FutureBuilder<bool>(
      future: MukaiGlass.available,
      initialData: false,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        final bool glass = snapshot.data == true;
        // The native view cannot read the Flutter theme; hand it the
        // brightness so light mode gets light glass even when the system
        // disagrees with the app's forced mode.
        final bool isDark = MukaiColors.of(context).isDark;
        if (glass) MukaiGlass.syncAppearance(isDark: isDark);
        // Keep one platform view alive through sidebar drags and settling.
        // Replacing it with a painted blur destroys the native effect and
        // flashes when UIKit creates the replacement view.
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cornerRadius),
            boxShadow: glass
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? .18 : .08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            // Keep the content mounted when the native material becomes
            // available so a focused text field keeps its input connection.
            children: <Widget>[
              if (glass)
                Positioned.fill(
                  // Native backdrop views can punch through Flutter modal
                  // overlays. Omit them from composition while this route is
                  // covered, without recreating their UIKit views.
                  child: MukaiGlassVisibility(
                    child: UiKitView(
                      viewType: 'mukai/glass_pill',
                      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                      creationParams: <String, Object?>{
                        'cornerRadius': cornerRadius,
                        'dark': isDark,
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                    ),
                  ),
                ),
              KeyedSubtree(key: const ValueKey('content'), child: content),
            ],
          ),
        );
      },
    );
  }
}

/// A floating glass pill behind [child] on iOS 26+; a transparent box
/// everywhere else. ChatGPT-style grouping: pass a `Row` of icon buttons (with
/// [MukaiGlassDivider]s between them) to share one piece of glass.
class MukaiGlassPill extends StatelessWidget {
  const MukaiGlassPill({
    super.key,
    required this.child,
    this.height = 48,
    this.cornerRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final Widget child;
  final double height;
  final double? cornerRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return MukaiGlassSurface(
      cornerRadius: cornerRadius ?? height / 2,
      padding: padding,
      child: SizedBox(height: height, child: child),
    );
  }

  /// A single floating control. ChatGPT renders these as true circles, so the
  /// glass has to be as wide as it is tall: [diameter] (plus [padding] on both
  /// axes) instead of the wider `width = child + horizontal padding` a
  /// multi-button pill gets.
  static Widget circle({
    Key? key,
    required Widget child,
    double diameter = 48,
    double padding = 2,
  }) {
    final double inner = diameter - padding * 2;
    // AppBar gives leading widgets a tight 56 x 56 slot. Loosen that slot
    // before sizing the surface so its radius always describes a circle.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: diameter,
        child: MukaiGlassSurface(
          key: key,
          cornerRadius: diameter / 2,
          padding: EdgeInsets.all(padding),
          child: SizedBox(width: inner, height: inner, child: child),
        ),
      ),
    );
  }
}

/// Hairline separator between buttons that share one glass pill.
class MukaiGlassDivider extends StatelessWidget {
  const MukaiGlassDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 1,
        height: 20,
        color: MukaiColors.of(context).hairline,
      ),
    );
  }
}

/// Consistent back control for AppBar leading slots.
class MukaiGlassBackButton extends StatelessWidget {
  const MukaiGlassBackButton({super.key});

  @override
  Widget build(BuildContext context) => MukaiGlassPill.circle(
    diameter: 44,
    padding: 0,
    child: IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: const BackButtonIcon(),
      iconSize: 20,
      onPressed: () => Navigator.of(context).maybePop(),
    ),
  );
}

/// Retains native view state while covered, then gently restores its material.
class MukaiGlassVisibility extends StatelessWidget {
  const MukaiGlassVisibility({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final current = ModalRoute.isCurrentOf(context) != false;
    return ValueListenableBuilder<Map<Route<dynamic>, int>>(
      valueListenable: MukaiGlass._coveredRoutes,
      child: child,
      builder: (context, covers, child) {
        final visible = current && !covers.containsKey(route);
        return AnimatedOpacity(
          opacity: visible ? 1 : 0,
          // Hide before a modal can overlap the native material; restore only
          // after it has left. No platform view is removed from the tree.
          duration: !visible || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}
