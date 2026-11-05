import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/api/api_client.dart';

class PushTarget {
  const PushTarget(this.workspaceId, this.conversationId, this.botId);
  final String workspaceId, conversationId, botId;
}

abstract class PushStore {
  Future<Map<String, dynamic>> read();
  Future<void> write(Map<String, dynamic> value);
}

class KeychainPushStore implements PushStore {
  static const _storage = FlutterSecureStorage();
  @override
  Future<Map<String, dynamic>> read() async {
    final text = await _storage.read(key: 'mukai.push.v1');
    if (text == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> write(Map<String, dynamic> value) =>
      _storage.write(key: 'mukai.push.v1', value: jsonEncode(value));
}

abstract class PushNative {
  bool get supported;
  Stream<Map<String, dynamic>> get events;
  Future<Map<String, dynamic>> register();
  Future<List<Map<String, dynamic>>> drain();
  Future<void> visible(String serverId, String conversationId);
  Future<void> clear();
  Future<void> openSettings();
  void dispose();
}

class APNsBridge implements PushNative {
  static const _channel = MethodChannel('com.mukai.mobile/push');
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  APNsBridge() {
    if (supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'event' || call.arguments is! Map) return false;
        _events.add(Map<String, dynamic>.from(call.arguments as Map));
        return true;
      });
    }
  }
  @override
  bool get supported => !kIsWeb && Platform.isIOS;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Future<Map<String, dynamic>> register() async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>('register') ?? {},
  );
  @override
  Future<List<Map<String, dynamic>>> drain() async => [
    for (final value in await _channel.invokeListMethod<dynamic>('drain') ?? [])
      if (value is Map) Map<String, dynamic>.from(value),
  ];
  @override
  Future<void> visible(String serverId, String conversationId) =>
      _channel.invokeMethod('visible', {
        'serverId': serverId,
        'conversationId': conversationId,
      });
  @override
  Future<void> clear() => _channel.invokeMethod('clear');
  @override
  Future<void> openSettings() => _channel.invokeMethod('openSettings');
  @override
  void dispose() {
    if (supported) _channel.setMethodCallHandler(null);
    unawaited(_events.close());
  }
}

class RelayException implements Exception {
  const RelayException(this.status, [this.code]);
  final int status;
  final String? code;
}

typedef RelayCall =
    Future<Map<String, dynamic>> Function(
      Uri uri,
      String method,
      Map<String, dynamic> body,
      String credential,
    );
Future<Map<String, dynamic>> relayCall(
  Uri uri,
  String method,
  Map<String, dynamic> body,
  String credential,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $credential');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 8192) throw const RelayException(502);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      try {
        final value = jsonDecode(utf8.decode(bytes));
        final candidate = value is Map ? value['code'] : null;
        if (candidate is String &&
            RegExp(r'^apns_[A-Za-z_]{1,64}$').hasMatch(candidate)) {
          code = candidate;
        }
      } catch (_) {
        /* An HTML proxy error is still reported by HTTP status. */
      }
      throw RelayException(response.statusCode, code);
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  } finally {
    client.close(force: true);
  }
}

/// Developer configures the relay once in the signed app; recipients only grant permission.
class MobilePushController extends ChangeNotifier {
  MobilePushController({
    required this.onOpen,
    PushNative? native,
    PushStore? store,
    RelayCall? relay,
    this.relayUrl = const String.fromEnvironment('MUKAI_PUSH_RELAY_URL'),
  }) : native = native ?? APNsBridge(),
       store = store ?? KeychainPushStore(),
       relay = relay ?? relayCall {
    _subscription = this.native.events.listen(_event);
  }
  final void Function(PushTarget) onOpen;
  final PushNative native;
  final PushStore store;
  final RelayCall relay;
  final String relayUrl;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  Map<String, dynamic> _box = {};
  bool _loaded = false, _disposed = false;
  int _generation = 0;
  String? _lastVisible;
  void _cancelSetup() {
    ++_generation;
    final proof = _challenge;
    if (proof != null && !proof.isCompleted) proof.complete('');
    _connecting = null;
  }

  MukaiApiClient? _api;
  String? serverId;
  String status = 'Not connected';
  bool get enabled => _box['enabled'] != false;
  bool get ready => status == 'Notifications connected';
  Map<String, dynamic>? get _current => _box['current'] is Map
      ? Map<String, dynamic>.from(_box['current'] as Map)
      : null;
  Future<void>? _connecting;
  Future<void> _writes = Future.value();
  Completer<String>? _challenge;
  String? _attempt;
  final List<Map<String, dynamic>> _pendingEvents = [];
  final Set<String> _seen = {};
  void _log(String message) {
    if (!kDebugMode) return;
    final time = DateTime.now().toIso8601String().substring(11, 19);
    final line = '$time $message';
    debugPrint('[Mukai push] $line');
  }

  String _failure(Object error) {
    if (error is MissingPluginException) {
      return 'Native push bridge missing; rebuild and reinstall the iOS app.';
    }
    if (error is PlatformException) {
      if (error.code == 'apns_unavailable' && error.details is Map) {
        final details = error.details as Map;
        final reason = (details['reason'] as String? ?? '').replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        return 'Apple registration: ${details['domain']} ${details['code']} ${reason.length > 200 ? reason.substring(0, 200) : reason}';
      }
      return 'iOS error: ${error.code}';
    }
    if (error is SocketException) {
      return error.message.toLowerCase().contains('host lookup')
          ? 'DNS lookup failed; the relay hostname could not be resolved.'
          : 'Network connection failed (OS ${error.osError?.errorCode ?? 'unknown'}).';
    }
    if (error is HandshakeException) return 'HTTPS/TLS handshake failed.';
    if (error is TimeoutException) return 'Timed out.';
    if (error is RelayException) {
      return 'Relay HTTP ${error.status}${error.code == null ? '' : ': ${error.code}'}';
    }
    if (error is ApiException) {
      return 'Mukai API HTTP ${error.statusCode ?? 'error'}';
    }
    if (error is FormatException) {
      return 'Invalid notification configuration or response.';
    }
    return 'Unexpected ${error.runtimeType}';
  }

  void _status(String value) {
    status = value;
    _log(value);
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    if (!_loaded) {
      _box = await store.read();
      _loaded = true;
    }
  }

  Future<void> _save() {
    final snapshot = jsonDecode(jsonEncode(_box)) as Map<String, dynamic>;
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => store.write(snapshot));
    return _writes;
  }

  static String randomSecret() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
  static String randomId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Uri origin(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Relay requires HTTPS.');
    }
    return Uri.parse(uri.origin);
  }

  Future<void> connect(MukaiApiClient api) {
    if (_connecting != null && identical(_api, api)) return _connecting!;
    _cancelSetup();
    _api = api;
    final generation = _generation;
    late final Future<void> task;
    task = _connect(api, generation).whenComplete(() {
      if (identical(_connecting, task)) _connecting = null;
    });
    _connecting = task;
    return task;
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Notification setup canceled.');
    }
  }

  Future<void> _connect(MukaiApiClient api, int generation) async {
    if (!native.supported) return;
    var step = 'Loading notification settings';
    void progress(String message) {
      step = message;
      _log(message);
    }

    try {
      progress(step);
      await _load();
      _check(generation);
      progress('Cleaning up old registrations');
      await _cleanup();
      _check(generation);
      if (!enabled) {
        _status('Notifications off');
        return;
      }
      progress('Reading push configuration from Mukai');
      final config = Map<String, dynamic>.from(
        await api.request('/push/config') as Map,
      );
      _check(generation);
      serverId = config['serverId'] as String;
      final configured = relayUrl.isNotEmpty
          ? relayUrl
          : config['relayUrl'] as String? ?? '';
      if (configured.isEmpty) {
        _status('Notifications unavailable on this build');
        return;
      }
      final base = origin(configured);
      _log(
        'Relay: ${base.origin} (${relayUrl.isNotEmpty ? 'build override' : 'Mukai configuration'})',
      );
      progress('Reading queued notifications');
      for (final event in [..._pendingEvents, ...await native.drain()]) {
        _event(event);
      }
      _pendingEvents.clear();
      _status('Connecting notifications…');
      progress('Registering this iPhone with Apple APNs');
      final apple = await native.register().timeout(
        const Duration(seconds: 25),
      );
      _check(generation);
      if (apple['authorized'] != true) {
        await _retire();
        _check(generation);
        _status('Allow notifications in iPhone Settings');
        return;
      }
      _log(
        'Apple registration succeeded (${apple['environment'] == 'production' ? 'production' : 'sandbox'})',
      );
      var registration = _current;
      if (registration != null &&
          (registration['serverId'] != serverId ||
              registration['relayUrl'] != base.origin)) {
        await _retire();
        _check(generation);
        registration = null;
      }
      registration ??= {
        'installationId': randomId(),
        'manageToken': randomSecret(),
        'relayUrl': base.origin,
        'serverId': serverId,
        'serverUrl': api.serverUrl,
      };
      final needsProof =
          registration['deliveryToken'] is! String ||
          registration['deviceToken'] != apple['deviceToken'] ||
          registration['environment'] != apple['environment'] ||
          DateTime.now().millisecondsSinceEpoch -
                  (registration['registeredAt'] as int? ?? 0) >
              30 * 86400000;
      _box['current'] = registration;
      progress('Saving pairing settings');
      await _save();
      _check(generation);
      if (needsProof) {
        final attempt = randomId();
        _attempt = attempt;
        final proof = Completer<String>();
        _challenge = proof;
        final path = '/v1/devices/${registration['installationId']}';
        progress('Sending pairing challenge to relay');
        await relay(base.resolve('$path/challenge'), 'POST', {
          'deviceToken': apple['deviceToken'],
          'environment': apple['environment'],
          'serverId': serverId,
          'attemptId': attempt,
        }, registration['manageToken'] as String);
        _check(generation);
        progress('Waiting for Apple pairing notification');
        for (final event in await native.drain()) {
          _event(event);
        }
        final challenge = await proof.future.timeout(
          const Duration(seconds: 35),
        );
        _check(generation);
        progress('Confirming pairing with relay');
        final confirmation = await relay(
          base.resolve('$path/confirm'),
          'POST',
          {'challenge': challenge, 'attemptId': attempt},
          registration['manageToken'] as String,
        );
        _check(generation);
        final delivery = confirmation['deliveryToken'];
        if (delivery is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(delivery) ||
            confirmation['serverId'] != serverId) {
          throw const FormatException('Invalid pairing response.');
        }
        registration.addAll({
          'deliveryToken': delivery,
          'deviceToken': apple['deviceToken'],
          'environment': apple['environment'],
          'registeredAt': DateTime.now().millisecondsSinceEpoch,
        });
        _box['current'] = registration;
        await _save();
      }
      _check(generation);
      progress('Registering delivery with Mukai');
      await api.request(
        '/push/devices',
        method: 'POST',
        body: {
          'installationId': registration['installationId'],
          'relayUrl': registration['relayUrl'],
          'deliveryToken': registration['deliveryToken'],
        },
      );
      _check(generation);
      _status('Notifications connected');
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _log('$step failed: ${_failure(error)}');
        _status('Could not connect notifications. Try again.');
      }
    } finally {
      if (generation == _generation) {
        _challenge = null;
        _attempt = null;
      }
    }
  }

  void _event(Map<String, dynamic> event) {
    if (_disposed) return;
    if (event['type'] == 'pairing') {
      if (event['installationId'] == _current?['installationId'] &&
          event['attemptId'] == _attempt &&
          event['challenge'] is String &&
          !(_challenge?.isCompleted ?? true)) {
        _challenge!.complete(event['challenge'] as String);
      }
      return;
    }
    if (event['type'] == 'tokenChanged') {
      if (_api != null) unawaited(connect(_api!));
      return;
    }
    if (event['type'] != 'event' || !enabled) return;
    if (serverId == null) {
      if (_pendingEvents.length < 32) _pendingEvents.add(event);
      return;
    }
    if (event['serverId'] != serverId) return;
    final fields = ['workspaceId', 'conversationId', 'botId', 'eventId'];
    if (!fields.every(
      (key) =>
          event[key] is String &&
          RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(event[key] as String),
    )) {
      return;
    }
    if (!_seen.add(event['eventId'] as String)) return;
    if (_seen.length > 256) _seen.remove(_seen.first);
    onOpen(
      PushTarget(
        event['workspaceId'] as String,
        event['conversationId'] as String,
        event['botId'] as String,
      ),
    );
  }

  Future<void> _retire() async {
    final current = _current;
    if (current == null) return;
    _box['revocations'] = [...(_box['revocations'] as List? ?? []), current];
    _box.remove('current');
    await _save();
    try {
      if (_api?.serverUrl == current['serverUrl']) {
        await _api!
            .request(
              '/push/devices/${current['installationId']}',
              method: 'DELETE',
            )
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      /* Relay revocation still prevents delivery. */
    }
    await _cleanup();
  }

  Future<void> _cleanup() async {
    final retained = <dynamic>[];
    for (final item in _box['revocations'] as List? ?? []) {
      try {
        await relay(
          origin(
            item['relayUrl'] as String,
          ).resolve('/v1/devices/${item['installationId']}'),
          'DELETE',
          {},
          item['manageToken'] as String,
        );
      } catch (_) {
        retained.add(item);
      }
    }
    _box['revocations'] = retained.take(32).toList();
    await _save();
  }

  Future<void> setEnabled(bool value) async {
    await _load();
    _box['enabled'] = value;
    await _save();
    if (value && _api != null) {
      await connect(_api!);
    } else {
      _cancelSetup();
      await _retire();
      _status('Notifications off');
    }
  }

  Future<void> disconnect() async {
    _cancelSetup();
    serverId = null;
    if (!native.supported) {
      _api = null;
      return;
    }
    await _load();
    await _retire();
    _api = null;
    await native.clear();
    _status('Not connected');
  }

  Future<void> test() async {
    if (!ready || _api == null) {
      throw StateError('Connect notifications first.');
    }
    await _api!.request('/push/test', method: 'POST');
  }

  void visible(String? conversationId) {
    final key = '${serverId ?? ''}:${conversationId ?? ''}';
    if (_lastVisible == key) return;
    _lastVisible = key;
    if (native.supported) {
      unawaited(
        native
            .visible(serverId ?? '', conversationId ?? '')
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSetup();
    unawaited(_subscription.cancel());
    native.dispose();
    super.dispose();
  }
}
