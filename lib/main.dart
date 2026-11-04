/// Entry point. Composition root: store, controllers, app.
///
/// Nothing below this file knows how many screens exist or where data comes
/// from — swap [MukaiDemoRepository] for a backend-backed repository and the
/// rest of the client is unchanged.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/connection_store.dart';
import 'design/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _reportErrors();

  final SettingsStore store = PersistentSettingsStore(
    await SharedPreferences.getInstance(),
  );
  final AppearanceController appearance = AppearanceController(
    loader: () =>
        MukaiPreferences.fromJson(store.read(MukaiPreferences.storageKey)),
    saver: (MukaiPreferences preferences) =>
        store.write(MukaiPreferences.storageKey, preferences.toJson()),
  );

  runApp(
    MukaiApp(appearance: appearance, connectionStore: const ConnectionStore()),
  );
}

/// Surface framework errors loudly while this is a preview, instead of a
/// silent grey screen. A production build would forward these to a reporter.
void _reportErrors() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint('[mukai] ${details.library}: ${details.exceptionAsString()}');
    }
  };

  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stack) {
        if (kDebugMode) debugPrint('[mukai] uncaught: $error');
        // false = still report it; the preview should never hide a real bug.
        return false;
      };
}
