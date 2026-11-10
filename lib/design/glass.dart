/// Apple's iOS 26 liquid glass as a pill backdrop for Flutter controls.
///
/// The material itself is rendered natively (`UIGlassEffect` inside a
/// platform view, see `native/ios/AppDelegate.swift`) because no Flutter
/// primitive refracts like glass; the buttons stay ordinary Flutter widgets
/// drawn on top. Wherever the native material is unavailable — Android, web,
/// or iOS below 26 — [MukaiGlassPill] adds literally nothing, so the fallback
/// is exactly the pre-glass UI.
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

/// A floating glass pill behind [child] on iOS 26+; a transparent box
/// everywhere else. ChatGPT-style grouping: pass a `Row` of icon buttons (with
/// [MukaiGlassDivider]s between them) to share one piece of glass.
class MukaiGlassPill extends StatelessWidget {
  const MukaiGlassPill({
    super.key,
    required this.child,
    this.height = 44,
    this.cornerRadius,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double height;
  final double? cornerRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final double radius = cornerRadius ?? height / 2;
    final Widget content =
        Padding(padding: padding, child: Center(child: child));
    return SizedBox(
      height: height,
      child: FutureBuilder<bool>(
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
                  creationParams: <String, Object?>{'cornerRadius': radius},
                  creationParamsCodec: const StandardMessageCodec(),
                ),
              ),
              content,
            ],
          );
        },
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
