import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/connection_store.dart';
import '../core/push_notifications.dart';
import '../data/api/api_client.dart';
import '../data/api/api_repository.dart';
import '../data/demo/demo_repository.dart';
import '../design/appearance.dart';
import '../design/theme.dart';
import '../features/auth/auth_screen.dart';
import '../state/session_controller.dart';
import 'home_shell.dart';
import 'scope.dart';

class MukaiApp extends StatefulWidget {
  const MukaiApp({
    super.key,
    required this.appearance,
    this.session,
    this.connectionStore,
  });
  final AppearanceController appearance;

  /// Explicitly injected demo sessions are used by widget tests and previews.
  final SessionController? session;
  final ConnectionStore? connectionStore;
  @override
  State<MukaiApp> createState() => _MukaiAppState();
}

class _MukaiAppState extends State<MukaiApp> with WidgetsBindingObserver {
  late SessionController _session;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final MobilePushController _push;
  PushTarget? _pushTarget;
  bool _authenticated = false;
  bool _restoring = false;
  String _url = '';
  String? _error;
  bool _disconnecting = false;
  Future<void> _credentialWrite = Future<void>.value();

  Future<void> _persist(Future<void> Function() action) {
    final next = _credentialWrite.then((_) => action());
    _credentialWrite = next.catchError((Object _) {});
    return next;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session ?? SessionController(MukaiDemoRepository());
    _push = MobilePushController(
      onOpen: (target) {
        if (mounted && _authenticated) setState(() => _pushTarget = target);
      },
    );
    widget.appearance.hydrate();
    if (widget.connectionStore != null) _restore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final api = _session.api;
    if (state == AppLifecycleState.resumed &&
        _authenticated &&
        !_disconnecting &&
        api != null) {
      unawaited(_push.connect(api));
    }
  }

  MukaiApiClient? _prepared;
  StoredConnection? _saved;

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      _saved = await widget.connectionStore!.read();
      final saved = _saved;
      if (saved != null) {
        _url = MukaiApiClient.normalizeServerUrl(saved.url);
        if (saved.expiresAt.isAfter(DateTime.now())) {
          final api = _createClient(saved.url, saved: saved);
          _prepared = api;
          final status = await api.request('/auth/status');
          if (status is Map && status['authenticated'] == true) {
            await _enter(api, saved.expiresAt);
          } else {
            api.close();
            _prepared = null;
            _error = 'Sign in to your Mukai again.';
          }
        }
      }
    } catch (error) {
      _prepared?.close();
      _prepared = null;
      _error = 'Reconnect to your Mukai. $error';
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  MukaiApiClient _createClient(String url, {StoredConnection? saved}) {
    final api = MukaiApiClient.device(
      url,
      sessionToken: saved?.sessionToken,
      accessCredentials: saved?.cloudflare,
    );
    api.onUnauthorized = () => _returnToLogin(
      api,
      'Your Mukai session has expired. Sign in again.',
      forgetSession: true,
    );
    api.onAccessRequired = () => _returnToLogin(
      api,
      'Cloudflare needs you to sign in again. Connect to continue.',
    );
    api.onAccessChanged = (_) async {
      if (mounted &&
          !_disconnecting &&
          _authenticated &&
          identical(_session.api, api) &&
          _saved != null) {
        final updated = StoredConnection(
          url: api.base.toString(),
          sessionToken: _saved!.sessionToken,
          expiresAt: _saved!.expiresAt,
          cloudflare: api.accessCredentials,
        );
        await _persist(() async {
          if (mounted &&
              !_disconnecting &&
              _authenticated &&
              identical(_session.api, api)) {
            await widget.connectionStore?.save(updated);
          }
        });
        if (mounted &&
            !_disconnecting &&
            _authenticated &&
            identical(_session.api, api)) {
          _saved = updated;
        }
      }
    };
    return api;
  }

  void _returnToLogin(
    MukaiApiClient api,
    String message, {
    bool forgetSession = false,
  }) {
    if (!mounted ||
        _disconnecting ||
        !_authenticated ||
        !identical(_session.api, api)) {
      return;
    }
    unawaited(_push.disconnect());
    _pushTarget = null;
    final previous = _session;
    if (forgetSession && _saved != null) {
      _saved = StoredConnection(
        url: _saved!.url,
        sessionToken: '',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
        cloudflare: api.accessCredentials,
      );
    }
    setState(() {
      _authenticated = false;
      _url = api.serverUrl;
      _error = message;
      _session = SessionController(MukaiDemoRepository());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  Future<bool> _prepare(String url) async {
    _prepared?.close();
    _prepared = null;
    final normalized = MukaiApiClient.normalizeBase(url).toString();
    final saved = _saved?.url == normalized ? _saved : null;
    final api = _createClient(url, saved: saved);
    if (saved != null && !saved.expiresAt.isAfter(DateTime.now())) {
      api.sessionToken = null;
    }
    _prepared = api;
    try {
      final status = await api.request('/auth/status', interactiveAccess: true);
      if (status is! Map || status['authenticated'] is! bool) {
        throw const ApiException(
          'This server did not return Mukai sign-in information.',
        );
      }
      if (status['configured'] == false) {
        throw const ApiException(
          'Finish setting up your Mukai owner account in its web app, then connect here.',
        );
      }
      if (status['authenticated'] == true && saved != null) {
        await _enter(api, saved.expiresAt);
        return true;
      }
      api.sessionToken = null;
      _url = api.serverUrl;
      return false;
    } catch (_) {
      api.close();
      if (identical(_prepared, api)) _prepared = null;
      rethrow;
    }
  }

  Future<void> _signIn(String username, String password) async {
    if (_prepared == null && await _prepare(_url)) return;
    final api = _prepared!;
    final response = await api.request(
      '/auth/device',
      method: 'POST',
      body: {'username': username.trim(), 'password': password},
    );
    if (response is! Map ||
        response['sessionToken'] is! String ||
        response['expiresAt'] is! String) {
      throw const ApiException(
        'This Mukai server needs an update to support mobile sign-in.',
      );
    }
    api.sessionToken = response['sessionToken'] as String;
    final expiresAt = DateTime.parse(response['expiresAt'] as String);
    await _enter(api, expiresAt);
  }

  Future<void> _enter(MukaiApiClient api, DateTime expiresAt) async {
    final repository = ApiRepository(api);
    SessionController? next;
    try {
      await repository.refresh();
      next = SessionController(repository);
      await next.loadRecents();
      if (next.hasError) throw ApiException(next.error!);
      final saved = StoredConnection(
        url: api.base.toString(),
        sessionToken: api.sessionToken!,
        expiresAt: expiresAt,
        cloudflare: api.accessCredentials,
      );
      await _persist(() async => widget.connectionStore?.save(saved));
      if (!mounted) {
        next.dispose();
        return;
      }
      _saved = saved;
      _prepared = null;
      final previous = _session;
      setState(() {
        _session = next!;
        _authenticated = true;
        _url = api.serverUrl;
        _error = null;
      });
      unawaited(_push.connect(api));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous != widget.session) previous.dispose();
      });
    } catch (_) {
      // Keep the login client available for a retry after a transient load error.
      // SessionController.dispose closes its repository, so recreate next time.
      if (next != null) {
        next.dispose();
        _prepared = null;
      }
      rethrow;
    }
  }

  void _demoConnected() {
    _session.loadRecents();
    setState(() => _authenticated = true);
  }

  Future<void> _disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    try {
      await _push.disconnect();
    } catch (_) {
      // Server logout still revokes the device session if local cleanup fails.
    }
    _pushTarget = null;
    try {
      final api = _session.api;
      if (api != null) {
        try {
          await api.request('/auth/device-logout', method: 'POST');
        } catch (_) {
          // Local sign-out remains possible while offline. Server sessions expire.
        }
      }
      await _persist(() async => widget.connectionStore?.clear());
    } catch (_) {
      if (mounted) {
        _messenger.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Could not remove the saved connection. Try again.'),
          ),
        );
      }
      _disconnecting = false;
      return;
    }
    _disconnecting = false;
    if (!mounted) return;
    final previous = _session;
    setState(() {
      _session = SessionController(MukaiDemoRepository());
      _authenticated = false;
      _error = null;
      _saved = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (previous != widget.session) previous.dispose();
    });
  }

  @override
  void dispose() {
    _prepared?.close();
    WidgetsBinding.instance.removeObserver(this);
    _push.dispose();
    if (_session != widget.session) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MukaiScope(
    appearance: widget.appearance,
    session: _session,
    push: _push,
    child: ListenableBuilder(
      listenable: widget.appearance,
      builder: (context, _) {
        final preferences = widget.appearance.preferences;
        return MaterialApp(
          title: 'Mukai',
          scaffoldMessengerKey: _messenger,
          debugShowCheckedModeBanner: false,
          themeMode: widget.appearance.themeMode,
          theme: mukaiTheme(preferences, Brightness.light),
          darkTheme: mukaiTheme(preferences, Brightness.dark),
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: mukaiOverlayStyle(MukaiColors.of(context)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: _restoring
              ? const Scaffold(
                  body: Center(child: CircularProgressIndicator.adaptive()),
                )
              : _authenticated
              ? HomeShell(
                  key: ObjectKey(_session),
                  onDisconnect: _disconnect,
                  pushTarget: _pushTarget,
                )
              : AuthScreen(
                  onAuthenticated: _demoConnected,
                  onPrepare: widget.session == null ? _prepare : null,
                  onSignIn: widget.session == null ? _signIn : null,
                  initialUrl: _url,
                  connectionError: _error,
                ),
        );
      },
    ),
  );
}
