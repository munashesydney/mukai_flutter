import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

/// Opaque Cloudflare OAuth tokens. Persist only in secure device storage.
class AccessCredentials {
  const AccessCredentials({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenEndpoint,
    required this.clientId,
    required this.issuer,
    required this.resource,
    required this.expiresAt,
    this.authorizationEndpoint,
  });

  final String accessToken;
  final String? refreshToken;
  final String tokenEndpoint;
  final String clientId;
  final String issuer;
  final String resource;
  final DateTime? expiresAt;
  final String? authorizationEndpoint;

  bool get needsRefresh =>
      expiresAt != null &&
      !expiresAt!.isAfter(
        DateTime.now().toUtc().add(const Duration(seconds: 60)),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenEndpoint': tokenEndpoint,
    'clientId': clientId,
    'issuer': issuer,
    'resource': resource,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    if (authorizationEndpoint != null)
      'authorizationEndpoint': authorizationEndpoint,
  };

  factory AccessCredentials.fromJson(Map<String, dynamic> value) {
    String requiredString(String key) {
      final field = value[key];
      if (field is! String || field.isEmpty) {
        throw const FormatException('Invalid saved Cloudflare session.');
      }
      return field;
    }

    final expiry = value['expiresAt'];
    if (expiry != null &&
        (expiry is! String || DateTime.tryParse(expiry) == null)) {
      throw const FormatException('Invalid saved Cloudflare session expiry.');
    }
    final refresh = value['refreshToken'];
    final authorization = value['authorizationEndpoint'];
    if ((refresh != null && refresh is! String) ||
        (authorization != null && authorization is! String)) {
      throw const FormatException('Invalid saved Cloudflare session.');
    }
    return AccessCredentials(
      accessToken: requiredString('accessToken'),
      refreshToken: refresh as String?,
      tokenEndpoint: requiredString('tokenEndpoint'),
      clientId: requiredString('clientId'),
      issuer: requiredString('issuer'),
      resource: requiredString('resource'),
      expiresAt: expiry == null
          ? null
          : DateTime.parse(expiry as String).toUtc(),
      authorizationEndpoint: authorization as String?,
    );
  }
}

class CloudflareAccessException implements Exception {
  const CloudflareAccessException(this.message, {required this.code});
  final String message;
  final String code;
  @override
  String toString() => message;
}

typedef AccessAuthorize =
    Future<AuthorizationTokenResponse> Function(
      AuthorizationTokenRequest request,
    );
typedef AccessRefresh = Future<TokenResponse> Function(TokenRequest request);

/// Cloudflare Access Managed OAuth: RFC 9728 discovery, public DCR, and
/// authorization-code+PKCE through the operating system's AppAuth browser.
///
/// This does not read browser cookies, follow API redirects, use Cloudflare
/// administrator credentials, or send a Mukai token to an OAuth endpoint.
/// References:
/// https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/managed-oauth/
/// https://developers.cloudflare.com/cloudflare-one/access-controls/authenticate-agents/
class CloudflareAccess {
  CloudflareAccess({
    FlutterAppAuth? appAuth,
    AccessAuthorize? authorizeAndExchangeCode,
    AccessRefresh? token,
    HttpClient? httpClient,
    this.allowInsecureLoopbackForTesting = false,
  }) : _authorize =
           authorizeAndExchangeCode ??
           (appAuth ?? const FlutterAppAuth()).authorizeAndExchangeCode,
       _token = token ?? (appAuth ?? const FlutterAppAuth()).token,
       _http = httpClient ?? HttpClient(),
       _ownsHttp = httpClient == null {
    _http.connectionTimeout = const Duration(seconds: 15);
  }

  static const redirectUri = 'com.mukai.mobile:/oauth/callback';
  static const setupMessage =
      'Enable Managed OAuth and Dynamic Client Registration on the Cloudflare '
      'Access application, and allow the exact redirect URI '
      'com.mukai.mobile:/oauth/callback. Then sign in again.';
  final AccessAuthorize _authorize;
  final AccessRefresh _token;
  final HttpClient _http;
  final bool _ownsHttp;

  /// Only for loopback fixture servers; never enables arbitrary HTTP issuers.
  final bool allowInsecureLoopbackForTesting;

  /// Precise enough to distinguish an origin's invalid Mukai token from an
  /// Access challenge. Cloudflare's classic browser-only redirect is detected
  /// for actionable setup guidance, never followed with credentials.
  static bool isAccessChallenge({
    required int statusCode,
    required Map<String, String> headers,
    Uri? requestUri,
  }) {
    final normalized = <String, String>{
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    if (statusCode == 401 &&
        _metadataPointer(normalized['www-authenticate']) != null) {
      return true;
    }
    if (statusCode < 300 || statusCode >= 400) return false;
    final location = normalized['location'];
    if (location == null) return false;
    final parsed = Uri.tryParse(location);
    if (parsed == null) return false;
    final target = parsed.hasAuthority
        ? parsed
        : requestUri?.resolveUri(parsed);
    if (target == null ||
        !target.hasAuthority ||
        !<String>['http', 'https'].contains(target.scheme) ||
        target.userInfo.isNotEmpty) {
      return false;
    }
    return target.path.startsWith('/cdn-cgi/access/login') &&
        (_teamHost(target.host) ||
            (requestUri != null && target.origin == requestUri.origin));
  }

  Future<AccessCredentials> authorize(Uri base, {String? challenge}) async {
    _secureUri(base);
    var pointer = _metadataPointer(challenge);
    if (pointer == null) {
      final probe = await _request(base);
      pointer = _metadataPointer(probe.headers['www-authenticate']);
      if (pointer == null &&
          isAccessChallenge(
            statusCode: probe.status,
            headers: probe.headers,
            requestUri: base,
          )) {
        throw const CloudflareAccessException(
          setupMessage,
          code: 'managed_oauth_required',
        );
      }
      if (pointer == null) {
        throw const CloudflareAccessException(
          setupMessage,
          code: 'managed_oauth_required',
        );
      }
    }

    final metadataUri = Uri.tryParse(pointer);
    if (metadataUri == null || !metadataUri.hasAuthority) {
      throw _invalidMetadata();
    }
    _secureUri(metadataUri);
    if (metadataUri.origin != base.origin) {
      throw const CloudflareAccessException(
        'Cloudflare returned resource metadata for a different server.',
        code: 'invalid_metadata',
      );
    }
    _secureUri(metadataUri);
    final resourceMetadata = await _json(metadataUri);
    final resource = _requiredUri(resourceMetadata, 'resource');
    _secureUri(resource);
    if (resource.origin != base.origin || !_covers(resource, base)) {
      throw const CloudflareAccessException(
        'Cloudflare returned an OAuth resource that does not match this Mukai URL.',
        code: 'invalid_resource',
      );
    }
    final servers = resourceMetadata['authorization_servers'];
    if (servers is! List || servers.isEmpty || servers.first is! String) {
      throw const CloudflareAccessException(
        setupMessage,
        code: 'managed_oauth_required',
      );
    }
    final issuer = _issuer(servers.first as String);
    final team = resourceMetadata['team_domain'];
    if (team is String && _issuer(team).origin != issuer.origin) {
      throw const CloudflareAccessException(
        'Cloudflare OAuth discovery returned inconsistent team domains.',
        code: 'invalid_metadata',
      );
    }
    // RFC 8414 inserts the well-known component before an issuer path.
    final issuerPath = issuer.path.replaceAll(RegExp(r'/+$'), '');
    final discoveryUri = issuer.replace(
      path: '/.well-known/oauth-authorization-server$issuerPath',
    );
    final server = await _json(discoveryUri);
    final declaredIssuer = _issuer(_requiredString(server, 'issuer'));
    if (_canonical(declaredIssuer) != _canonical(issuer)) {
      throw const CloudflareAccessException(
        'Cloudflare OAuth discovery returned a different issuer.',
        code: 'invalid_metadata',
      );
    }
    _requireSupport(server, 'response_types_supported', 'code');
    _requireSupport(server, 'grant_types_supported', 'authorization_code');
    _requireSupport(server, 'token_endpoint_auth_methods_supported', 'none');
    _requireSupport(server, 'code_challenge_methods_supported', 'S256');
    if (server['registration_endpoint'] is! String) {
      throw const CloudflareAccessException(
        setupMessage,
        code: 'registration_unavailable',
      );
    }
    final authorization = _endpoint(server, 'authorization_endpoint', issuer);
    final tokenEndpoint = _endpoint(server, 'token_endpoint', issuer);
    final registration = _endpoint(server, 'registration_endpoint', issuer);
    final grants = <String>[
      'authorization_code',
      if (_supports(server, 'grant_types_supported', 'refresh_token'))
        'refresh_token',
    ];
    final registered = await _json(
      registration,
      method: 'POST',
      body: <String, dynamic>{
        'client_name': 'Mukai for iOS',
        'client_uri': 'https://usemukai.com/',
        'logo_uri': 'https://usemukai.com/mascots/mukai-logo.webp',
        'redirect_uris': <String>[redirectUri],
        'token_endpoint_auth_method': 'none',
        'grant_types': grants,
        'response_types': <String>['code'],
        'resource': resource.toString(),
      },
      registration: true,
    );
    final clientId = _requiredString(registered, 'client_id');
    if (registered['token_endpoint_auth_method'] != 'none') {
      throw const CloudflareAccessException(
        'Cloudflare did not register a public native client. $setupMessage',
        code: 'invalid_registration',
      );
    }
    final redirects = registered['redirect_uris'];
    if (redirects is! List || !redirects.contains(redirectUri)) {
      throw const CloudflareAccessException(
        'Cloudflare did not allow Mukai’s callback. $setupMessage',
        code: 'callback_not_allowed',
      );
    }
    final scopes = <String>[
      if (_supports(server, 'scopes_supported', 'offline_access'))
        'offline_access',
    ];
    try {
      final result = await _authorize(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: authorization.toString(),
            tokenEndpoint: tokenEndpoint.toString(),
          ),
          additionalParameters: <String, String>{
            'resource': resource.toString(),
          },
          scopes: scopes,
        ),
      );
      return _credentials(
        result,
        clientId: clientId,
        issuer: issuer.toString(),
        resource: resource.toString(),
        tokenEndpoint: tokenEndpoint.toString(),
        authorizationEndpoint: authorization.toString(),
      );
    } on FlutterAppAuthUserCancelledException {
      throw const CloudflareAccessException(
        'Cloudflare sign-in was cancelled.',
        code: 'cancelled',
      );
    } on PlatformException {
      throw const CloudflareAccessException(
        'Cloudflare sign-in did not complete. Check Access policy and the allowed '
        'Mukai callback, then try again.',
        code: 'authorization_failed',
      );
    }
  }

  Future<AccessCredentials> refresh(AccessCredentials credentials) async {
    final issuer = _issuer(credentials.issuer);
    final tokenEndpoint = Uri.tryParse(credentials.tokenEndpoint);
    final authorization = Uri.tryParse(
      credentials.authorizationEndpoint ?? credentials.tokenEndpoint,
    );
    final resource = Uri.tryParse(credentials.resource);
    if (tokenEndpoint == null || authorization == null || resource == null) {
      throw const CloudflareAccessException(
        'Sign in to Cloudflare Access again.',
        code: 'invalid_session',
      );
    }
    _secureUri(resource);
    _sameTeamEndpoint(tokenEndpoint, issuer);
    _sameTeamEndpoint(authorization, issuer);
    final refreshToken = credentials.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const CloudflareAccessException(
        'Sign in to Cloudflare Access again.',
        code: 'token_expired',
      );
    }
    try {
      final result = await _token(
        TokenRequest(
          credentials.clientId,
          redirectUri,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: authorization.toString(),
            tokenEndpoint: tokenEndpoint.toString(),
          ),
          refreshToken: refreshToken,
          grantType: 'refresh_token',
          additionalParameters: <String, String>{
            'resource': resource.toString(),
          },
        ),
      );
      return _credentials(
        result,
        clientId: credentials.clientId,
        issuer: credentials.issuer,
        resource: credentials.resource,
        tokenEndpoint: credentials.tokenEndpoint,
        authorizationEndpoint: credentials.authorizationEndpoint,
        previousRefreshToken: refreshToken,
      );
    } on PlatformException {
      throw const CloudflareAccessException(
        'Your Cloudflare Access session expired. Sign in again.',
        code: 'token_expired',
      );
    }
  }

  AccessCredentials _credentials(
    TokenResponse result, {
    required String clientId,
    required String issuer,
    required String resource,
    required String tokenEndpoint,
    required String? authorizationEndpoint,
    String? previousRefreshToken,
  }) {
    final token = result.accessToken;
    if (token == null ||
        token.isEmpty ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(token) ||
        (result.tokenType != null &&
            result.tokenType!.toLowerCase() != 'bearer')) {
      throw const CloudflareAccessException(
        'Cloudflare did not return an access token. Sign in again.',
        code: 'missing_token',
      );
    }
    return AccessCredentials(
      accessToken: token,
      refreshToken: result.refreshToken ?? previousRefreshToken,
      tokenEndpoint: tokenEndpoint,
      clientId: clientId,
      issuer: issuer,
      resource: resource,
      expiresAt: result.accessTokenExpirationDateTime?.toUtc(),
      authorizationEndpoint: authorizationEndpoint,
    );
  }

  Uri _issuer(String value) {
    // Cloudflare's resource metadata may name team_domain without a scheme.
    final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
    if (uri == null) throw _invalidMetadata();
    _secureUri(uri);
    if (!_teamHost(uri.host) && !_testLoopback(uri)) {
      throw const CloudflareAccessException(
        'The discovered authorization server is not a Cloudflare Access team.',
        code: 'invalid_issuer',
      );
    }
    if (uri.hasQuery || uri.hasFragment) throw _invalidMetadata();
    return uri;
  }

  Uri _endpoint(Map<String, dynamic> json, String key, Uri issuer) {
    final endpoint = _requiredUri(json, key);
    _sameTeamEndpoint(endpoint, issuer);
    return endpoint;
  }

  void _sameTeamEndpoint(Uri endpoint, Uri issuer) {
    _secureUri(endpoint);
    if (endpoint.origin != issuer.origin || endpoint.hasFragment) {
      throw const CloudflareAccessException(
        'Cloudflare OAuth endpoints must belong to the discovered team.',
        code: 'invalid_endpoint',
      );
    }
  }

  void _secureUri(Uri uri) {
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !_testLoopback(uri))) {
      throw const CloudflareAccessException(
        'Cloudflare Access requires secure HTTPS URLs.',
        code: 'insecure_endpoint',
      );
    }
  }

  bool _testLoopback(Uri uri) =>
      allowInsecureLoopbackForTesting &&
      uri.scheme == 'http' &&
      <String>['127.0.0.1', 'localhost', '::1'].contains(uri.host);

  static bool _teamHost(String host) =>
      RegExp(r'^[a-zA-Z0-9-]+\.cloudflareaccess\.com$').hasMatch(host);

  static bool _covers(Uri resource, Uri target) {
    final root = resource.path.replaceAll(RegExp(r'/+$'), '');
    return root.isEmpty ||
        target.path == root ||
        target.path.startsWith('$root/');
  }

  static String _canonical(Uri uri) =>
      uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), '')).toString();

  static String? _metadataPointer(String? challenge) {
    if (challenge == null ||
        !RegExp(
          r'(^|,)\s*Bearer\b',
          caseSensitive: false,
        ).hasMatch(challenge)) {
      return null;
    }
    final match = RegExp(
      r'resource_metadata\s*=\s*(?:"([^"\r\n]+)"|([^,\s]+))',
      caseSensitive: false,
    ).firstMatch(challenge);
    return match?.group(1) ?? match?.group(2);
  }

  static bool _supports(Map<String, dynamic> json, String key, String value) =>
      json[key] is List && (json[key] as List).contains(value);

  static void _requireSupport(
    Map<String, dynamic> json,
    String key,
    String value,
  ) {
    if (!_supports(json, key, value)) {
      throw const CloudflareAccessException(
        'Cloudflare Access must support public clients, authorization code, and '
        'S256 PKCE. $setupMessage',
        code: 'unsupported_oauth',
      );
    }
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) throw _invalidMetadata();
    return value;
  }

  static Uri _requiredUri(Map<String, dynamic> json, String key) {
    final uri = Uri.tryParse(_requiredString(json, key));
    if (uri == null || !uri.hasAuthority) throw _invalidMetadata();
    return uri;
  }

  static CloudflareAccessException _invalidMetadata() =>
      const CloudflareAccessException(
        'Cloudflare returned incomplete OAuth discovery data.',
        code: 'invalid_metadata',
      );

  Future<Map<String, dynamic>> _json(
    Uri uri, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool registration = false,
  }) async {
    final response = await _request(uri, method: method, body: body);
    if (response.status < 200 || response.status >= 300) {
      throw CloudflareAccessException(
        registration
            ? 'Cloudflare did not allow this native client. $setupMessage'
            : setupMessage,
        code: registration ? 'registration_rejected' : 'managed_oauth_required',
      );
    }
    try {
      final value = jsonDecode(response.body);
      if (value is! Map) throw _invalidMetadata();
      return Map<String, dynamic>.from(value);
    } on FormatException {
      throw _invalidMetadata();
    }
  }

  Future<_AccessResponse> _request(
    Uri uri, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    _secureUri(uri);
    try {
      final request = await _http
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final chunks = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        chunks.addAll(chunk);
        if (chunks.length > 256 * 1024) throw _invalidMetadata();
      }
      final headers = <String, String>{};
      response.headers.forEach(
        (name, values) => headers[name.toLowerCase()] = values.join(', '),
      );
      return _AccessResponse(response.statusCode, headers, utf8.decode(chunks));
    } on CloudflareAccessException {
      rethrow;
    } on TimeoutException {
      throw const CloudflareAccessException(
        'Cloudflare Access took too long to respond. Try again.',
        code: 'network',
      );
    } on IOException {
      throw const CloudflareAccessException(
        'Cannot reach Cloudflare Access securely. Check your network and URL.',
        code: 'network',
      );
    }
  }

  void close() {
    if (_ownsHttp) _http.close(force: true);
  }
}

class _AccessResponse {
  const _AccessResponse(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final String body;
}
