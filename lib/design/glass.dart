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
  static const MethodChannel _channel =
      MethodChannel('com.mukai.mobile/glass');
  static Future<bool>? _probe;

  static Future<bool> get available => _probe ??= _detect();

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
  const MukaiGlassProbe({
    super.key,
    required this.builder,
    this.child,
  });

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
        if (snapshot.data != true) return content;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: UiKitView(
                viewType: 'mukai/glass_pill',
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                creationParams: <String, Object?>{'cornerRadius': cornerRadius},
                creationParamsCodec: const StandardMessageCodec(),
              ),
            ),
            content,
          ],
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
