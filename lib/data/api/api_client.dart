import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../mukai_repository.dart';
import '../auth/cloudflare_access.dart';

class DownloadedContent {
  const DownloadedContent(
    this.bytes, {
    this.mediaType = 'application/octet-stream',
    this.name = 'File',
  });
  final Uint8List bytes;
  final String mediaType, name;
}

class AccessRequiredException extends ApiException {
  const AccessRequiredException(super.message);
}

class ApiException extends MukaiDataException {
  const ApiException(super.message, {this.statusCode});
  final int? statusCode;
}

/// Owner API transport. Never puts credentials in URLs or follows redirects.
class MukaiApiClient {
  /// Retained for integrations that explicitly use the owner API token.
  MukaiApiClient(String baseUrl, String token, {HttpClient? httpClient})
    : this._(baseUrl, token: _validatedToken(token), httpClient: httpClient);

  static String _validatedToken(String token) {
    if (token.trim().isEmpty) {
      throw const ApiException('Enter your Mukai token.');
    }
    return token.trim();
  }

  MukaiApiClient.device(
    String baseUrl, {
    String? sessionToken,
    AccessCredentials? accessCredentials,
    CloudflareAccess? access,
    HttpClient? httpClient,
  }) : this._(
         baseUrl,
         sessionToken: sessionToken,
         accessCredentials: accessCredentials,
         access: access,
         httpClient: httpClient,
       );

  MukaiApiClient._(
    String baseUrl, {
    String? token,
    this.sessionToken,
    AccessCredentials? accessCredentials,
    CloudflareAccess? access,
    HttpClient? httpClient,
  }) : base = normalizeBase(baseUrl),
       _token = token,
       _accessCredentials = accessCredentials,
       _access = access ?? CloudflareAccess(),
       _http = httpClient ?? HttpClient() {
    if (accessCredentials != null) {
      // Access tokens belong to a Cloudflare application. Its metadata can
      // identify the exact challenged endpoint, including /api/auth/status.
      // Keep saved credentials pinned to this origin and API path boundary.
      final resource = Uri.tryParse(accessCredentials.resource);
      final root = resource?.path.replaceAll(RegExp(r'/+$'), '');
      if (resource == null ||
          !resource.hasAuthority ||
          resource.origin != base.origin ||
          (root!.isNotEmpty &&
              base.path != root &&
              !base.path.startsWith('$root/') &&
              !root.startsWith('${base.path}/'))) {
        throw const ApiException(
          'The saved Cloudflare session belongs to another server. Connect again.',
        );
      }
    }
    _http.connectionTimeout = const Duration(seconds: 15);
  }

  final Uri base;
  String get serverUrl => normalizeServerUrl(base.toString());

  static String normalizeServerUrl(String value) {
    final api = normalizeBase(value);
    return api
        .replace(path: api.path.replaceFirst(RegExp(r'/api$'), ''))
        .toString();
  }

  final String? _token;
  String? sessionToken;
  final HttpClient _http;
  final CloudflareAccess _access;
  AccessCredentials? _accessCredentials;
  AccessCredentials? get accessCredentials => _accessCredentials;
  Future<AccessCredentials>? _refreshing;
  bool _closed = false;
  void Function()? onUnauthorized;
  void Function()? onAccessRequired;
  Future<void> Function(AccessCredentials credentials)? onAccessChanged;

  Future<void> _refreshAccess() async {
    final credentials = _accessCredentials;
    if (credentials == null) return;
    try {
      final pending = _refreshing ??= _access.refresh(credentials);
      final refreshed = await pending;
      if (!identical(_accessCredentials, refreshed)) {
        _accessCredentials = refreshed;
        await onAccessChanged?.call(refreshed);
      }
    } finally {
      _refreshing = null;
    }
  }

  final Set<HttpClient> _eventClients = {};
  void cancelEvents() {
    for (final client in _eventClients.toList()) {
      client.close(force: true);
    }
    _eventClients.clear();
  }

  static Uri normalizeBase(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        !parsed.hasAuthority ||
        !['https', 'http'].contains(parsed.scheme) ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const ApiException(
        'Enter a full Mukai URL, such as https://mukai.example.',
      );
    }
    var path = parsed.path.replaceAll(RegExp(r'/+$'), '');
    if (!path.endsWith('/api')) path += '/api';
    return parsed.replace(path: path);
  }

  Uri uri(String path) {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('://')) {
      throw ArgumentError('Use a relative API path.');
    }
    return Uri.parse('${base.toString()}$path');
  }

  Future<HttpClientResponse> _open(
    String path,
    String method, {
    Object? body,
    List<int>? bytes,
    Map<String, String> headers = const {},
    HttpClient? client,
    bool interactiveAccess = false,
    bool accessRetried = false,
  }) async {
    if (_closed) throw const ApiException('This connection has been closed.');
    try {
      if (_accessCredentials?.needsRefresh == true && !accessRetried) {
        try {
          await _refreshAccess();
        } catch (_) {
          if (interactiveAccess) {
            _accessCredentials = await _access.authorize(uri(path));
            await onAccessChanged?.call(_accessCredentials!);
          } else {
            onAccessRequired?.call();
            throw const AccessRequiredException(
              'Cloudflare sign-in has expired. Connect again to continue.',
            );
          }
        }
      }
      final request = await (client ?? _http)
          .openUrl(method, uri(path))
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      if (_accessCredentials != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${_accessCredentials!.accessToken}',
        );
      } else if (_token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (sessionToken != null) {
        request.headers.set('X-Mukai-Session', sessionToken!);
      }
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      } else if (bytes != null) {
        request.add(bytes);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseHeaders = <String, String>{};
        response.headers.forEach(
          (key, values) =>
              responseHeaders[key.toLowerCase()] = values.join(', '),
        );
        if (CloudflareAccess.isAccessChallenge(
          statusCode: response.statusCode,
          headers: responseHeaders,
          requestUri: uri(path),
        )) {
          await response.drain<void>();
          if (!accessRetried) {
            if (interactiveAccess) {
              _accessCredentials = await _access.authorize(
                uri(path),
                challenge: responseHeaders['www-authenticate'],
              );
              await onAccessChanged?.call(_accessCredentials!);
            } else if (_accessCredentials?.refreshToken != null) {
              try {
                await _refreshAccess();
              } catch (_) {
                onAccessRequired?.call();
                throw const AccessRequiredException(
                  'Cloudflare needs you to sign in again.',
                );
              }
            } else {
              onAccessRequired?.call();
              throw const AccessRequiredException(
                'Sign in to Cloudflare to reach your Mukai.',
              );
            }
            return await _open(
              path,
              method,
              body: body,
              bytes: bytes,
              headers: headers,
              client: client,
              interactiveAccess: interactiveAccess,
              accessRetried: true,
            );
          }
          onAccessRequired?.call();
          throw const AccessRequiredException(
            'Cloudflare did not grant access. Check its application policy and try again.',
          );
        }
        if (response.statusCode == 401 &&
            (sessionToken != null || _token != null)) {
          onUnauthorized?.call();
        }
        final text = await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 20));
        String? message;
        try {
          final value = jsonDecode(text);
          if (value is Map && value['error'] is String) {
            message = value['error'] as String;
          }
        } catch (_) {}
        throw ApiException(
          response.statusCode == 401
              ? message ?? 'Your Mukai session has expired. Sign in again.'
              : response.statusCode >= 300 && response.statusCode < 400
              ? 'Mukai redirected the API request. Use its final server URL.'
              : message ??
                    'Mukai returned HTTP ${response.statusCode}. Check the server address and try again.',
          statusCode: response.statusCode,
        );
      }
      return response;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'Mukai took too long to respond. Check the connection and try again.',
      );
    } on HandshakeException {
      throw const ApiException(
        'The secure connection failed. Check the server certificate and URL.',
      );
    } on SocketException {
      throw const ApiException(
        'Cannot reach Mukai. Check the server URL and your network.',
      );
    } on HttpException {
      throw const ApiException('The connection to Mukai was interrupted.');
    }
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    bool interactiveAccess = false,
  }) async {
    final response = await _open(
      path,
      method,
      body: body,
      interactiveAccess: interactiveAccess,
    );
    final text = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 30));
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      throw const ApiException(
        'This address did not return Mukai API data. Check the Base URL.',
      );
    }
  }

  Future<dynamic> upload(String path, String name, List<int> bytes) async {
    final response = await _open(
      path,
      'POST',
      bytes: bytes,
      headers: {
        'X-Filename': Uri.encodeComponent(name),
        'Content-Type': 'application/octet-stream',
      },
    );
    return jsonDecode(await utf8.decoder.bind(response).join());
  }

  Future<Uint8List> download(
    String path, {
    String method = 'GET',
    Object? body,
    bool interactiveAccess = false,
  }) async {
    return (await downloadContent(
      path,
      method: method,
      body: body,
      interactiveAccess: interactiveAccess,
    )).bytes;
  }

  Future<DownloadedContent> downloadContent(
    String path, {
    String method = 'GET',
    Object? body,
    bool interactiveAccess = false,
    int maxBytes = 128 * 1024 * 1024,
  }) async {
    final response = await _open(
      path,
      method,
      body: body,
      interactiveAccess: interactiveAccess,
    );
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const ApiException(
          'This file is too large to preview on this phone.',
        );
      }
      bytes.add(chunk);
    }
    final disposition = response.headers.value('content-disposition') ?? '';
    final encodedName = RegExp(
      r"filename\*=UTF-8''(.+)$",
      caseSensitive: false,
    ).firstMatch(disposition)?[1];
    var name =
        RegExp(
          r'filename="?([^";]+)',
          caseSensitive: false,
        ).firstMatch(disposition)?[1] ??
        'File';
    if (encodedName != null) {
      try {
        name = Uri.decodeComponent(encodedName);
      } catch (_) {}
    }
    name = name
        .split(RegExp(r'[\\/]+'))
        .last
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
    return DownloadedContent(
      bytes.takeBytes(),
      mediaType:
          response.headers.contentType?.mimeType ?? 'application/octet-stream',
      name: name.isEmpty ? 'File' : name,
    );
  }

  Stream<Map<String, dynamic>> events(String path, Object body) async* {
    final eventClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _eventClients.add(eventClient);
    try {
      final response = await _open(
        path,
        'POST',
        body: body,
        headers: {'Accept': 'text/event-stream'},
        client: eventClient,
      );
      var finished = false;
      try {
        await for (final line
            in response
                .timeout(const Duration(seconds: 90))
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          final value = line.trim();
          if (value.isEmpty ||
              value.startsWith(':') ||
              value.startsWith('event:') ||
              value.startsWith('id:') ||
              value.startsWith('retry:')) {
            continue;
          }
          final payload = value.startsWith('data:')
              ? value.substring(5).trim()
              : value;
          final event = Map<String, dynamic>.from(jsonDecode(payload) as Map);
          yield event;
          if (event['type'] == 'done' || event['type'] == 'error') {
            finished = true;
          }
        }
      } on FormatException {
        throw const ApiException(
          'Mukai returned an unreadable response stream. Refresh the saved conversation.',
        );
      } on TimeoutException {
        throw const ApiException(
          'The response stream timed out. Your saved conversation can be refreshed.',
        );
      }
      if (!finished) {
        throw const ApiException(
          'The response was interrupted. Refresh the saved conversation before retrying.',
        );
      }
    } finally {
      _eventClients.remove(eventClient);
      eventClient.close(force: true);
    }
  }

  void close() {
    _closed = true;
    cancelEvents();
    _http.close(force: true);
    _access.close();
  }
}

String newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
}
