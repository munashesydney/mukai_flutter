/// Login logic for the setup-code flow, kept out of the widget.
///
/// Mukai is hosted by the user: the browser/mobile client proves access with a
/// code the local backend prints at startup. The verifier is injected so the
/// real POST to `/auth/setup-code` can replace the demo without UI changes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

enum AuthStage { idle, connecting, connected, failed }

abstract interface class SetupCodeVerifier {
  /// Completes when the backend accepts the code; throws otherwise.
  Future<void> verify(String code);
}

/// Accepts any plausible code, and fails on one known-bad value so the error
/// state can be demonstrated without a running backend.
class DemoSetupCodeVerifier implements SetupCodeVerifier {
  DemoSetupCodeVerifier({
    this.latency = const Duration(milliseconds: 1100),
    this.minimumLength = 8,
  });

  final Duration latency;
  final int minimumLength;

  static const List<String> rejectedCodes = <String>['00000000', 'expired00'];

  @override
  Future<void> verify(String code) async {
    await Future<void>.delayed(latency);
    if (rejectedCodes.contains(code.toLowerCase())) {
      throw const SetupCodeRejectedException(
        'That code expired. Restart Mukai to print a new one.',
      );
    }
    if (code.trim().length < minimumLength) {
      throw const SetupCodeRejectedException(
        'That does not look like a setup code yet.',
      );
    }
  }
}

class SetupCodeRejectedException implements Exception {
  const SetupCodeRejectedException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthController extends ChangeNotifier {
  AuthController(this._verifier);

  final SetupCodeVerifier _verifier;

  AuthStage _stage = AuthStage.idle;
  String? _error;
  int _attempts = 0;

  AuthStage get stage => _stage;
  String? get error => _error;
  int get attempts => _attempts;
  bool get isConnecting => _stage == AuthStage.connecting;
  bool get isConnected => _stage == AuthStage.connected;

  /// Submittable once the field looks like a code and nothing is in flight.
  bool canSubmit(String code) =>
      !_isBusy && code.trim().length >= 8 && !_isExpiredCode(code);

  bool get _isBusy => _stage == AuthStage.connecting;

  bool _isExpiredCode(String code) =>
      DemoSetupCodeVerifier.rejectedCodes.contains(code.trim().toLowerCase());

  /// Verifies the code. Returns true when the client may continue to step 2.
  Future<bool> submit(String code) async {
    final String trimmed = code.trim();
    if (!canSubmit(trimmed)) return false;

    _stage = AuthStage.connecting;
    _error = null;
    _attempts++;
    notifyListeners();

    try {
      await _verifier.verify(trimmed);
      _stage = AuthStage.connected;
      _error = null;
      notifyListeners();
      return true;
    } on SetupCodeRejectedException catch (failure) {
      _stage = AuthStage.failed;
      _error = failure.message;
      notifyListeners();
      return false;
    } catch (failure) {
      _stage = AuthStage.failed;
      _error = 'Could not reach Mukai. Check that the server is running.';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    if (_error == null && _stage != AuthStage.failed) return;
    _error = null;
    _stage = AuthStage.idle;
    notifyListeners();
  }
}
