/// Persistence seam for user preferences.
///
/// Deliberately not a plugin: this client currently ships with zero third-party
/// dependencies, so the default store lives for the life of the process. Back
/// this interface with `shared_preferences` (or with the Mukai backend) and the
/// chosen theme survives a relaunch — two lines in `main.dart`, see README.
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SettingsStore {
  Map<String, dynamic>? read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
}

/// In-memory store. Same interface, no dependencies, easy to swap.
class MemorySettingsStore implements SettingsStore {
  final Map<String, Map<String, dynamic>> _values =
      <String, Map<String, dynamic>>{};

  @override
  Map<String, dynamic>? read(String key) => _values[key];

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    _values[key] = Map<String, dynamic>.unmodifiable(value);
  }
}

class PersistentSettingsStore implements SettingsStore {
  PersistentSettingsStore(this.preferences);
  final SharedPreferences preferences;
  @override
  Map<String, dynamic>? read(String key) {
    final value = preferences.getString(key);
    if (value == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    await preferences.setString(key, jsonEncode(value));
  }
}
