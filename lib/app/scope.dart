/// One inherited scope for the app's controllers.
///
/// Controllers notify themselves, so [updateShouldNotify] is false: dependents
/// rebuild on `notifyListeners`, not on widget identity changes. Swapping this
/// for `provider`/`riverpod` later touches only this file and `app.dart`.
library;

import 'package:flutter/material.dart';

import '../design/appearance.dart';
import '../core/push_notifications.dart';
import '../state/session_controller.dart';

class MukaiScope extends InheritedWidget {
  const MukaiScope({
    super.key,
    required this.session,
    required this.appearance,
    this.push,
    required super.child,
  });

  final SessionController session;
  final AppearanceController appearance;
  final MobilePushController? push;

  static MukaiScope _read(BuildContext context) {
    final MukaiScope? scope = context
        .dependOnInheritedWidgetOfExactType<MukaiScope>();
    assert(scope != null, 'No MukaiScope found — wrap the app in MukaiApp.');
    return scope!;
  }

  static MobilePushController? pushOf(BuildContext context) =>
      _read(context).push;

  static SessionController sessionOf(BuildContext context) =>
      _read(context).session;
  static AppearanceController appearanceOf(BuildContext context) =>
      _read(context).appearance;

  @override
  bool updateShouldNotify(MukaiScope oldWidget) => false;
}
