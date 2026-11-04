import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/data/auth/cloudflare_access.dart';
import 'package:mukai_flutter/data/api/api_client.dart';

AuthorizationTokenResponse _authorized() => AuthorizationTokenResponse(
  'oauth:access',
  'oauth:refresh',
  DateTime.utc(2030),
  null,
  'bearer',
  <String>[],
  null,
  null,
);
TokenResponse _refreshed({String? refresh = 'oauth:rotated'}) => TokenResponse(
  'oauth:new',
  refresh,
  DateTime.utc(2031),
  null,
  'bearer',
  <String>[],
  null,
);
Future<TokenResponse> _unusedRefresh(TokenRequest request) async =>
    _refreshed();
Matcher _failure(String code) => isA<CloudflareAccessException>().having(
  (error) => error.code,
  'code',
  code,
);

class _Discovery {
  late HttpServer server;
  final requests =
      <
        ({
          String method,
          Uri uri,
          dynamic body,
          String? authorization,
          String? mukai,
        })
      >[];
  String protectedPath = '/protected';
  bool acceptAuthorized = false;
  String? metadataRedirect;
  String? resourceOverride;
  String? metadataPointer;
  String? declaredIssuer;
  String? tokenEndpoint;
  bool registrationAllowed = true;
  bool callbackAllowed = true;
  bool publicClient = true;
  bool pkce = true;
  Uri get base => Uri.parse('http://127.0.0.1:${server.port}$protectedPath');
  String get origin => base.origin;
  String get challenge =>
      'Bearer realm="OAuth", error="invalid_token", resource_metadata="${metadataPointer ?? '$origin/.well-known/cloudflare-access-protected-resource/'}"';
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        uri: request.uri,
        body: body.isEmpty ? null : jsonDecode(body),
        authorization: request.headers.value('authorization'),
        mukai: request.headers.value('x-mukai-session'),
      ));
      dynamic response;
      if (request.uri.path == '/classic') {
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          'https://team.cloudflareaccess.com/cdn-cgi/access/login/example',
        );
        await request.response.close();
        return;
      }
      if (acceptAuthorized &&
          request.headers.value('authorization') == 'Bearer oauth:access') {
        response = <String, dynamic>{
          'configured': true,
          'authenticated': false,
        };
      } else if (request.uri.path == protectedPath) {
        request.response.statusCode = 401;
        request.response.headers.set('www-authenticate', challenge);
        response = <String, dynamic>{'error': 'invalid_token'};
      } else if (request.uri.path ==
          Uri.parse(
            metadataPointer ??
                '$origin/.well-known/cloudflare-access-protected-resource/',
          ).path) {
        if (metadataRedirect != null) {
          request.response.statusCode = 302;
          request.response.headers.set('location', metadataRedirect!);
          await request.response.close();
          return;
        }
        response = <String, dynamic>{
          'resource': resourceOverride ?? origin,
          'team_domain': origin,
          'authorization_servers': <String>[origin],
        };
      } else if (request.uri.path ==
          '/.well-known/oauth-authorization-server') {
        response = <String, dynamic>{
          'issuer': declaredIssuer ?? origin,
          'authorization_endpoint':
              '$origin/cdn-cgi/access/oauth/authorization',
          'token_endpoint':
              tokenEndpoint ?? '$origin/cdn-cgi/access/oauth/token',
          if (registrationAllowed)
            'registration_endpoint':
                '$origin/cdn-cgi/access/oauth/registration',
          'response_types_supported': <String>['code'],
          'grant_types_supported': <String>[
            'authorization_code',
            'refresh_token',
          ],
          'token_endpoint_auth_methods_supported': <String>[
            if (publicClient) 'none' else 'client_secret_basic',
          ],
          'code_challenge_methods_supported': <String>[
            if (pkce) 'S256' else 'plain',
          ],
        };
      } else if (request.uri.path == '/cdn-cgi/access/oauth/registration') {
        response = <String, dynamic>{
          'client_id': 'native-client',
          'token_endpoint_auth_method': 'none',
          'redirect_uris': <String>[
            if (callbackAllowed)
              CloudflareAccess.redirectUri
            else
              'com.other:/callback',
          ],
        };
      } else {
        request.response.statusCode = 404;
        response = <String, dynamic>{'error': 'not_found'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
  }

  CloudflareAccess adapter({AccessAuthorize? authorize}) => CloudflareAccess(
    allowInsecureLoopbackForTesting: true,
    authorizeAndExchangeCode: authorize ?? (_) async => _authorized(),
    token: _unusedRefresh,
  );
}

void main() {
  group('Access challenge detection', () {
    test(
      'distinguishes OAuth and classic redirects from a rejected Mukai token',
      () {
        expect(
          CloudflareAccess.isAccessChallenge(
            statusCode: 401,
            headers: <String, String>{
              'WWW-Authenticate':
                  'Bearer resource_metadata="https://app.example/.well-known/cloudflare-access-protected-resource/"',
            },
          ),
          isTrue,
        );
        expect(
          CloudflareAccess.isAccessChallenge(
            statusCode: 401,
            headers: <String, String>{
              'WWW-Authenticate': 'Bearer realm="Mukai"',
            },
          ),
          isFalse,
        );
        expect(
          CloudflareAccess.isAccessChallenge(
            statusCode: 401,
            headers: <String, String>{'server': 'cloudflare'},
          ),
          isFalse,
        );
        expect(
          CloudflareAccess.isAccessChallenge(
            statusCode: 302,
            headers: <String, String>{
              'Location':
                  'https://team.cloudflareaccess.com/cdn-cgi/access/login/app',
            },
            requestUri: Uri.parse('https://app.example/api'),
          ),
          isTrue,
        );
        expect(
          CloudflareAccess.isAccessChallenge(
            statusCode: 302,
            headers: <String, String>{'location': 'https://evil.example/login'},
          ),
          isFalse,
        );
        expect(
          CloudflareAccess.isAccessChallenge(
            statusCode: 302,
            headers: <String, String>{
              'location': 'javascript:/cdn-cgi/access/login',
            },
            requestUri: Uri.parse('https://app.example/api'),
          ),
          isFalse,
        );
      },
    );
  });
  group('Managed OAuth discovery', () {
    late _Discovery fixture;
    late CloudflareAccess adapter;
    setUp(() async {
      fixture = _Discovery();
      await fixture.start();
      adapter = fixture.adapter();
    });
    tearDown(() async {
      adapter.close();
      await fixture.server.close(force: true);
    });

    test(
      'discovers the resource and registers a public native client before PKCE',
      () async {
        AuthorizationTokenRequest? authorization;
        adapter.close();
        adapter = fixture.adapter(
          authorize: (request) async {
            authorization = request;
            return _authorized();
          },
        );
        final credentials = await adapter.authorize(fixture.base);
        final registration = fixture.requests.singleWhere(
          (request) => request.method == 'POST',
        );
        expect(registration.uri.path, '/cdn-cgi/access/oauth/registration');
        expect(registration.body['client_uri'], 'https://usemukai.com/');
        expect(
          registration.body['logo_uri'],
          'https://usemukai.com/mascots/mukai-logo.webp',
        );
        expect(registration.body['redirect_uris'], <String>[
          CloudflareAccess.redirectUri,
        ]);
        expect(registration.body['token_endpoint_auth_method'], 'none');
        expect(registration.body['grant_types'], <String>[
          'authorization_code',
          'refresh_token',
        ]);
        expect(registration.body['resource'], fixture.origin);
        expect(authorization?.clientId, 'native-client');
        expect(authorization?.redirectUrl, CloudflareAccess.redirectUri);
        expect(authorization?.clientSecret, isNull);
        expect(authorization?.additionalParameters, <String, String>{
          'resource': fixture.origin,
        });
        expect(
          authorization?.serviceConfiguration?.tokenEndpoint,
          '${fixture.origin}/cdn-cgi/access/oauth/token',
        );
        expect(credentials.accessToken, 'oauth:access');
        expect(credentials.refreshToken, 'oauth:refresh');
        expect(credentials.resource, fixture.origin);
        expect(
          fixture.requests.every(
            (request) => request.authorization == null && request.mukai == null,
          ),
          isTrue,
        );
      },
    );
    test(
      'uses an existing challenge without probing the protected URL again',
      () async {
        await adapter.authorize(fixture.base, challenge: fixture.challenge);
        expect(
          fixture.requests.any((request) => request.uri.path == '/protected'),
          isFalse,
        );
      },
    );
    test(
      'API transport handles endpoint-specific resource metadata and restores it',
      () async {
        fixture.protectedPath = '/api/auth/status';
        fixture.metadataPointer =
            '${fixture.origin}/.well-known/cloudflare-access-protected-resource/api/auth/status';
        fixture.resourceOverride = fixture.base.toString();
        fixture.acceptAuthorized = true;
        final api = MukaiApiClient.device(fixture.origin, access: adapter);
        addTearDown(api.close);
        final result = await api.request(
          '/auth/status',
          interactiveAccess: true,
        );
        expect(result['configured'], true);
        expect(api.accessCredentials!.resource, fixture.base.toString());
        final restoredAdapter = fixture.adapter();
        final restored = MukaiApiClient.device(
          fixture.origin,
          access: restoredAdapter,
          accessCredentials: AccessCredentials.fromJson(
            api.accessCredentials!.toJson(),
          ),
        );
        addTearDown(restored.close);
        // Cloudflare grants application access; a challenged login path must not
        // prevent restoring that application session for sibling Mukai APIs.
        expect((await restored.request('/workspaces'))['configured'], true);
        final registration = fixture.requests.singleWhere(
          (r) => r.method == 'POST',
        );
        expect(registration.body['resource'], fixture.base.toString());
      },
    );
    test(
      'rejects a cross-origin resource metadata pointer before fetching it',
      () async {
        fixture.metadataPointer =
            'https://evil.example/.well-known/oauth-protected-resource';
        await expectLater(
          adapter.authorize(fixture.base),
          throwsA(_failure('invalid_metadata')),
        );
        expect(fixture.requests.length, 1);
      },
    );
    test('rejects mismatched resource and issuer metadata', () async {
      fixture.resourceOverride = 'https://other.example';
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('invalid_resource')),
      );
      fixture.resourceOverride = null;
      fixture.declaredIssuer = 'https://wrong.cloudflareaccess.com';
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('invalid_metadata')),
      );
    });
    test(
      'rejects cross-origin token endpoints before registration or browser launch',
      () async {
        fixture.tokenEndpoint = 'https://evil.example/token';
        await expectLater(
          adapter.authorize(fixture.base),
          throwsA(_failure('invalid_endpoint')),
        );
        expect(
          fixture.requests.any((request) => request.method == 'POST'),
          isFalse,
        );
      },
    );
    test('never follows a metadata redirect', () async {
      fixture.metadataRedirect = '/unexpected';
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('managed_oauth_required')),
      );
      expect(
        fixture.requests.any((request) => request.uri.path == '/unexpected'),
        isFalse,
      );
    });
    test('requires DCR, public client authentication and S256', () async {
      fixture.registrationAllowed = false;
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('registration_unavailable')),
      );
      fixture.registrationAllowed = true;
      fixture.publicClient = false;
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('unsupported_oauth')),
      );
      fixture.publicClient = true;
      fixture.pkce = false;
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('unsupported_oauth')),
      );
    });
    test('fails clearly when the callback is not registered', () async {
      fixture.callbackAllowed = false;
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('callback_not_allowed')),
      );
    });
    test('reports classic Access login as requiring Managed OAuth', () async {
      await expectLater(
        adapter.authorize(fixture.base.replace(path: '/classic')),
        throwsA(_failure('managed_oauth_required')),
      );
      expect(fixture.requests.length, 1);
    });
    test(
      'rejects insecure URLs unless explicit loopback-only test mode is used',
      () async {
        final strict = CloudflareAccess(
          authorizeAndExchangeCode: (_) async => _authorized(),
          token: _unusedRefresh,
        );
        addTearDown(strict.close);
        await expectLater(
          strict.authorize(fixture.base),
          throwsA(_failure('insecure_endpoint')),
        );
        await expectLater(
          adapter.authorize(Uri.parse('http://remote.example/api')),
          throwsA(_failure('insecure_endpoint')),
        );
      },
    );
    test(
      'turns browser cancellation into an actionable non-network result',
      () async {
        adapter.close();
        adapter = fixture.adapter(
          authorize: (_) async => throw PlatformException(
            code: 'authorize_and_exchange_code_failed',
          ),
        );
        await expectLater(
          adapter.authorize(fixture.base),
          throwsA(_failure('authorization_failed')),
        );
      },
    );
    test('distinguishes the user closing the browser', () async {
      adapter.close();
      adapter = fixture.adapter(
        authorize: (_) async => throw FlutterAppAuthUserCancelledException(
          code: 'user_cancelled',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        ),
      );
      await expectLater(
        adapter.authorize(fixture.base),
        throwsA(_failure('cancelled')),
      );
    });
  });
  group('Cloudflare token persistence and refresh', () {
    AccessCredentials credentials({
      String endpoint =
          'https://team.cloudflareaccess.com/cdn-cgi/access/oauth/token',
      String? refresh = 'oauth:old-refresh',
    }) => AccessCredentials(
      accessToken: 'oauth:old',
      refreshToken: refresh,
      tokenEndpoint: endpoint,
      clientId: 'native',
      issuer: 'https://team.cloudflareaccess.com',
      resource: 'https://app.example',
      expiresAt: DateTime.utc(2020),
    );
    test('round trips credentials and recognizes expiring tokens', () {
      final saved = credentials();
      final restored = AccessCredentials.fromJson(saved.toJson());
      expect(restored.toJson(), saved.toJson());
      expect(restored.needsRefresh, isTrue);
      expect(
        () => AccessCredentials.fromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
    test(
      'refreshes with the pinned endpoint, original resource and rotated token',
      () async {
        TokenRequest? captured;
        final adapter = CloudflareAccess(
          authorizeAndExchangeCode: (_) async => _authorized(),
          token: (request) async {
            captured = request;
            return _refreshed();
          },
        );
        addTearDown(adapter.close);
        final updated = await adapter.refresh(credentials());
        expect(captured?.clientId, 'native');
        expect(captured?.grantType, 'refresh_token');
        expect(captured?.refreshToken, 'oauth:old-refresh');
        expect(captured?.additionalParameters, <String, String>{
          'resource': 'https://app.example',
        });
        expect(
          captured?.serviceConfiguration?.tokenEndpoint,
          credentials().tokenEndpoint,
        );
        expect(updated.accessToken, 'oauth:new');
        expect(updated.refreshToken, 'oauth:rotated');
        expect(updated.needsRefresh, isFalse);
      },
    );
    test('preserves refresh token if the server does not rotate it', () async {
      final adapter = CloudflareAccess(
        authorizeAndExchangeCode: (_) async => _authorized(),
        token: (_) async => _refreshed(refresh: null),
      );
      addTearDown(adapter.close);
      expect(
        (await adapter.refresh(credentials())).refreshToken,
        'oauth:old-refresh',
      );
    });
    test(
      'does not send refresh credentials to a swapped token origin',
      () async {
        var called = false;
        final adapter = CloudflareAccess(
          authorizeAndExchangeCode: (_) async => _authorized(),
          token: (_) async {
            called = true;
            return _refreshed();
          },
        );
        addTearDown(adapter.close);
        await expectLater(
          adapter.refresh(credentials(endpoint: 'https://evil.example/token')),
          throwsA(_failure('invalid_endpoint')),
        );
        expect(called, isFalse);
        await expectLater(
          adapter.refresh(credentials(refresh: null)),
          throwsA(_failure('token_expired')),
        );
      },
    );
  });
}
