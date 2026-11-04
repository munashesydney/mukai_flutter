import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/core/push_notifications.dart';
import 'package:mukai_flutter/data/api/api_client.dart';

class MemoryStore implements PushStore {
  Map<String, dynamic> value = {};
  @override
  Future<Map<String, dynamic>> read() async =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<void> write(Map<String, dynamic> input) async {
    value = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
  }
}

class Native implements PushNative {
  final controller = StreamController<Map<String, dynamic>>.broadcast(
    sync: true,
  );
  bool authorized = true;
  int registrations = 0, clears = 0;
  @override
  bool get supported => true;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<Map<String, dynamic>> register() async {
    registrations++;
    return {
      'authorized': authorized,
      'deviceToken': 'ab' * 32,
      'environment': 'sandbox',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> drain() async => [];
  @override
  Future<void> visible(String a, String b) async {}
  @override
  Future<void> clear() async {
    clears++;
  }

  @override
  Future<void> openSettings() async {}
  @override
  void dispose() {
    unawaited(controller.close());
  }
}

class Api extends MukaiApiClient {
  Api() : super.device('https://mukai.example', sessionToken: 'a' * 64);
  final calls = <String>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    bool interactiveAccess = true,
  }) async {
    calls.add('$method $path');
    if (path == '/push/config') {
      return {'serverId': 'server-1', 'relayUrl': 'https://relay.example'};
    }
    return {'ok': true};
  }
}

void main() {
  late Native native;
  late MemoryStore store;
  late Api api;
  late MobilePushController push;
  late List<PushTarget> opened;
  late List<String> relayCalls;
  bool proof = true;
  setUp(() {
    native = Native();
    store = MemoryStore();
    api = Api();
    opened = [];
    relayCalls = [];
    proof = true;
    push = MobilePushController(
      native: native,
      store: store,
      onOpen: opened.add,
      relay: (uri, method, body, credential) async {
        relayCalls.add('$method ${uri.path}');
        expect(credential.length, 43);
        if (uri.path.endsWith('/challenge') && proof) {
          native.controller.add({
            'type': 'pairing',
            'installationId': uri.path.split('/')[3],
            'attemptId': body['attemptId'],
            'challenge': 'c' * 43,
          });
        }
        if (uri.path.endsWith('/confirm')) {
          return {'serverId': 'server-1', 'deliveryToken': 'd' * 43};
        }
        return {'ok': true};
      },
    );
  });
  tearDown(() {
    push.dispose();
    api.close();
  });
  test(
    'pairs through APNs proof and publishes only scoped delivery capability',
    () async {
      await push.connect(api);
      expect(push.ready, true);
      expect(relayCalls.where((s) => s.endsWith('/confirm')).length, 1);
      expect(api.calls, contains('POST /push/devices'));
      expect(store.value['current']['manageToken'], isNot('d' * 43));
      await push.connect(api);
      expect(relayCalls.where((s) => s.endsWith('/challenge')).length, 1);
      await push.test();
      expect(api.calls, contains('POST /push/test'));
    },
  );
  test('permission denial never pairs or registers backend', () async {
    native.authorized = false;
    await push.connect(api);
    expect(push.ready, false);
    expect(relayCalls, isEmpty);
    expect(api.calls, isNot(contains('POST /push/devices')));
  });
  test(
    'notification taps are deduplicated and restricted to current server with opaque IDs',
    () async {
      await push.connect(api);
      final event = {
        'type': 'event',
        'serverId': 'server-1',
        'workspaceId': 'default',
        'conversationId': 'chat-1',
        'botId': 'scout',
        'eventId': 'response:1',
      };
      native.controller.add({...event, 'serverId': 'other'});
      native.controller.add({
        ...event,
        'conversationId': 'https://evil.example',
      });
      native.controller.add(event);
      native.controller.add(event);
      expect(opened.length, 1);
      expect(opened.single.conversationId, 'chat-1');
    },
  );
  test(
    'disable revokes relay first and prevents reconnect or tap activation',
    () async {
      await push.connect(api);
      await push.setEnabled(false);
      expect(store.value['current'], isNull);
      expect(relayCalls.any((s) => s.startsWith('DELETE ')), true);
      expect(api.calls.any((s) => s.startsWith('DELETE /push/devices/')), true);
      final registrations = native.registrations;
      await push.connect(api);
      expect(native.registrations, registrations);
      native.controller.add({
        'type': 'event',
        'serverId': 'server-1',
        'workspaceId': 'default',
        'conversationId': 'chat-1',
        'botId': 'scout',
        'eventId': 'response:1',
      });
      expect(opened, isEmpty);
    },
  );
  test(
    'logout cancels pending proof, revokes installation and never publishes late registration',
    () async {
      proof = false;
      final task = push.connect(api);
      while (!relayCalls.any((s) => s.endsWith('/challenge'))) {
        await Future<void>.delayed(Duration.zero);
      }
      await push.disconnect();
      await task;
      expect(push.status, 'Not connected');
      expect(native.clears, 1);
      expect(api.calls, isNot(contains('POST /push/devices')));
      expect(store.value['current'], isNull);
    },
  );
  test(
    'relay origin and generated management credentials satisfy protocol',
    () {
      expect(
        MobilePushController.randomSecret(),
        matches(RegExp(r'^[A-Za-z0-9_-]{43}$')),
      );
      expect(
        MobilePushController.randomId(),
        matches(RegExp(r'^[a-f0-9-]{36}$')),
      );
      for (final value in [
        'http://relay.example',
        'https://relay.example/path',
        'https://user:pass@relay.example',
        'https://relay.example?x=1',
      ]) {
        expect(() => MobilePushController.origin(value), throwsFormatException);
      }
    },
  );
}
