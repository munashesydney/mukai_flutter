import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/auth/cloudflare_access.dart';

class StoredConnection {
  const StoredConnection({
    required this.url,
    required this.sessionToken,
    required this.expiresAt,
    this.cloudflare,
  });
  final String url, sessionToken;
  final DateTime expiresAt;
  final AccessCredentials? cloudflare;
  Map<String, dynamic> toJson() => {
    'url': url,
    'sessionToken': sessionToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (cloudflare != null) 'cloudflare': cloudflare!.toJson(),
  };
  factory StoredConnection.fromJson(Map<String, dynamic> json) =>
      StoredConnection(
        url: json['url'] as String,
        sessionToken: json['sessionToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        cloudflare: json['cloudflare'] == null
            ? null
            : AccessCredentials.fromJson(
                Map<String, dynamic>.from(json['cloudflare'] as Map),
              ),
      );
}

/// Device and Cloudflare sessions stay in Keychain. Passwords are never saved.
class ConnectionStore {
  const ConnectionStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'mukai.connection.v3';
  Future<StoredConnection?> read() async {
    // Discard the former master API-token login on upgrade.
    await _storage.delete(key: 'mukai.connection.v2');
    final value = await _storage.read(key: _key);
    return value == null
        ? null
        : StoredConnection.fromJson(
            Map<String, dynamic>.from(jsonDecode(value) as Map),
          );
  }

  Future<void> save(StoredConnection connection) =>
      _storage.write(key: _key, value: jsonEncode(connection.toJson()));
  Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: 'mukai.connection.v2');
  }
}
