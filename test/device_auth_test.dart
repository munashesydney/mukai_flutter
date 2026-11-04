import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/data/api/api_client.dart';
import 'package:mukai_flutter/data/auth/cloudflare_access.dart';

class _Access extends CloudflareAccess {
  _Access(this.resource);
  final String resource;
  int authorizations = 0, refreshes = 0;
  Uri? authorizedUri;
  bool failRefresh = false;
  Completer<void>? refreshGate;
  AccessCredentials credentials({bool expired = false}) => AccessCredentials(
    accessToken: expired ? 'oauth:old' : 'oauth:accepted',
    refreshToken: 'refresh-secret',
    clientId: 'public-client',
    issuer: 'https://team.cloudflareaccess.com',
    tokenEndpoint: 'https://team.cloudflareaccess.com/token',
    resource: resource,
    expiresAt: DateTime.now().add(Duration(minutes: expired ? -1 : 30)),
  );
  @override
  Future<AccessCredentials> authorize(Uri base, {String? challenge}) async {
    authorizations++;
    authorizedUri = base;
    return credentials();
  }

  @override
  Future<AccessCredentials> refresh(AccessCredentials credentials) async {
    refreshes++;
    await refreshGate?.future;
    if (failRefresh) {
      throw const CloudflareAccessException('Expired', code: 'token_expired');
    }
    return this.credentials();
  }
}

void main() {
  test(
    'server URLs hide API plumbing and normalize both supported input forms',
    () {
      for (final input in [
        'https://mukai.example',
        'https://mukai.example/',
        'https://mukai.example/api',
        'https://mukai.example/api/',
      ]) {
        expect(
          MukaiApiClient.normalizeServerUrl(input),
          'https://mukai.example',
        );
        expect(MukaiApiClient.normalizeBase(input).path, '/api');
      }
      expect(
        MukaiApiClient.normalizeServerUrl('https://host.example/mukai/api'),
        'https://host.example/mukai',
      );
      expect(
        MukaiApiClient.normalizeBase('https://host.example/mukai').path,
        '/mukai/api',
      );
    },
  );

  late HttpServer server;
  late String base;
  late _Access access;
  late Future<void> Function(HttpRequest request) handle;
  final clients = <MukaiApiClient>[];
  final seen = <Map<String, String?>>[];
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    access = _Access(base);
    seen.clear();
    handle = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    };
    server.listen((request) async {
      seen.add({
        'path': request.uri.path,
        'authorization': request.headers.value('authorization'),
        'session': request.headers.value('x-mukai-session'),
        'origin': request.headers.value('origin'),
      });
      await handle(request);
    });
  });
  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    access.close();
    await server.close(force: true);
  });
  MukaiApiClient client({String? session, AccessCredentials? credentials}) {
    final value = MukaiApiClient.device(
      base,
      sessionToken: session,
      accessCredentials: credentials,
      access: access,
    );
    clients.add(value);
    return value;
  }

  Future<void> challenge(HttpRequest request) async {
    request.response.statusCode = 401;
    request.response.headers.set(
      'www-authenticate',
      'Bearer resource_metadata="$base/.well-known/cloudflare-access-protected-resource/"',
    );
    request.response.write('{}');
    await request.response.close();
  }

  test(
    'login sends credentials only in JSON and does not treat wrong password as session expiry',
    () async {
      final api = client();
      var unauthorized = 0;
      api.onUnauthorized = () => unauthorized++;
      handle = (request) async {
        expect(request.method, 'POST');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'username': 'owner',
          'password': 'secret',
        });
        request.response.statusCode = 401;
        request.response.write(
          jsonEncode({'error': 'The username or password is incorrect.'}),
        );
        await request.response.close();
      };
      await expectLater(
        api.request(
          '/auth/device',
          method: 'POST',
          body: {'username': 'owner', 'password': 'secret'},
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('username or password'),
          ),
        ),
      );
      expect(unauthorized, 0);
      expect(seen.single['authorization'], isNull);
      expect(seen.single['session'], isNull);
      expect(seen.single['origin'], isNull);
      expect(seen.single['path'], '/api/auth/device');
    },
  );

  test('Mukai device and Cloudflare bearer credentials coexist', () async {
    final api = client(
      session: 'device-secret',
      credentials: access.credentials(),
    );
    await api.request('/workspaces');
    expect(seen.single['authorization'], 'Bearer oauth:accepted');
    expect(seen.single['session'], 'device-secret');
    expect(seen.single['origin'], isNull);
  });

  test('invalid device session invokes Mukai callback once', () async {
    final api = client(session: 'rejected');
    var unauthorized = 0;
    api.onUnauthorized = () => unauthorized++;
    handle = (request) async {
      request.response.statusCode = 401;
      request.response.write('{"error":"Authentication required"}');
      await request.response.close();
    };
    await expectLater(api.request('/workspaces'), throwsA(isA<ApiException>()));
    expect(unauthorized, 1);
    expect(access.authorizations, 0);
  });

  test(
    'interactive probe completes Cloudflare before retrying same Mukai endpoint',
    () async {
      handle = (request) async {
        if (request.headers.value('authorization') == null) {
          return challenge(request);
        }
        request.response.write('{"configured":true,"authenticated":false}');
        await request.response.close();
      };
      final api = client();
      var persisted = 0;
      api.onAccessChanged = (_) async => persisted++;
      final status = await api.request('/auth/status', interactiveAccess: true);
      expect(status['configured'], true);
      expect(access.authorizations, 1);
      expect(access.authorizedUri, Uri.parse('$base/api/auth/status'));
      expect(persisted, 1);
      expect(seen.length, 2);
      expect(seen.last['path'], '/api/auth/status');
      expect(seen.last['authorization'], 'Bearer oauth:accepted');
    },
  );

  test(
    'background challenges never open browser or invalidate Mukai session',
    () async {
      handle = challenge;
      final api = client(session: 'device-secret');
      var accessRequired = 0, unauthorized = 0;
      api.onAccessRequired = () => accessRequired++;
      api.onUnauthorized = () => unauthorized++;
      await expectLater(
        api.request('/workspaces'),
        throwsA(isA<AccessRequiredException>()),
      );
      expect(access.authorizations, 0);
      expect(accessRequired, 1);
      expect(unauthorized, 0);
    },
  );

  test(
    'concurrent requests share one refresh and persist rotated credentials once',
    () async {
      final api = client(
        session: 'device-secret',
        credentials: access.credentials(expired: true),
      );
      access.refreshGate = Completer<void>();
      var persisted = 0;
      api.onAccessChanged = (_) async => persisted++;
      final requests = Future.wait([
        api.request('/bots'),
        api.request('/spaces'),
        api.request('/workspaces'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(access.refreshes, 1);
      access.refreshGate!.complete();
      await requests;
      expect(persisted, 1);
      expect(seen.length, 3);
      expect(
        seen.every(
          (entry) => entry['authorization'] == 'Bearer oauth:accepted',
        ),
        true,
      );
    },
  );

  test(
    'failed refresh requires explicit reconnect and sends no expired token',
    () async {
      access.failRefresh = true;
      final api = client(
        session: 'device-secret',
        credentials: access.credentials(expired: true),
      );
      var required = 0;
      api.onAccessRequired = () => required++;
      await expectLater(
        api.request('/bots'),
        throwsA(isA<AccessRequiredException>()),
      );
      expect(required, 1);
      expect(access.authorizations, 0);
      expect(seen, isEmpty);
    },
  );

  test('ordinary redirects are not followed with either credential', () async {
    handle = (request) async {
      request.response.statusCode = 302;
      request.response.headers.set('location', '$base/elsewhere');
      await request.response.close();
    };
    final api = client(
      session: 'device-secret',
      credentials: access.credentials(),
    );
    await expectLater(api.request('/bots'), throwsA(isA<ApiException>()));
    expect(seen.length, 1);
    expect(access.authorizations, 0);
  });

  test(
    'saved Cloudflare resource rejects a sibling API prefix on the same host',
    () {
      final credentials = _Access('$base/api-other').credentials();
      expect(
        () => client(credentials: credentials),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'saved Cloudflare credentials cannot be attached to a different base URL',
    () {
      final credentials = _Access(
        'https://another-server.example',
      ).credentials();
      expect(
        () => client(credentials: credentials),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
