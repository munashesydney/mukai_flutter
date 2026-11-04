import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mukai_flutter/features/auth/auth_controller.dart';

class _ScriptedVerifier implements SetupCodeVerifier {
  _ScriptedVerifier({this.failure, this.gate});

  /// When set, verification throws this instead of succeeding.
  final Object? failure;

  /// When set, verification waits on it — used to hold the connecting state.
  final Completer<void>? gate;

  @override
  Future<void> verify(String code) async {
    await gate?.future;
    if (failure != null) throw failure!;
  }
}

void main() {
  group('canSubmit', () {
    test('needs something that looks like a code', () {
      final AuthController auth = AuthController(_ScriptedVerifier());
      expect(auth.canSubmit(''), isFalse);
      expect(auth.canSubmit('abc12'), isFalse);
      expect(auth.canSubmit('  abc12345  '), isTrue);
    });

    test('refuses the codes known to be dead', () {
      final AuthController auth = AuthController(_ScriptedVerifier());
      expect(auth.canSubmit('00000000'), isFalse);
      expect(auth.canSubmit('expired00'), isFalse);
    });
  });

  group('submit', () {
    test('a good code connects and lets the flow continue', () async {
      final AuthController auth = AuthController(_ScriptedVerifier());
      final bool ok = await auth.submit('a1b2c3d4');

      expect(ok, isTrue);
      expect(auth.isConnected, isTrue);
      expect(auth.stage, AuthStage.connected);
      expect(auth.attempts, 1);
      expect(auth.error, isNull);
    });

    test('a rejected code reports the backend copy', () async {
      final AuthController auth = AuthController(
        _ScriptedVerifier(
          failure: const SetupCodeRejectedException(
            'That code expired. Restart Mukai to print a new one.',
          ),
        ),
      );
      final bool ok = await auth.submit('a1b2c3d4');

      expect(ok, isFalse);
      expect(auth.stage, AuthStage.failed);
      expect(auth.error, contains('expired'));
    });

    test('an unreachable backend gets its own message', () async {
      final AuthController auth = AuthController(
        _ScriptedVerifier(failure: Exception('connection refused')),
      );
      await auth.submit('a1b2c3d4');
      expect(auth.error, contains('Could not reach Mukai'));
    });

    test('a second tap while connecting is ignored', () async {
      final Completer<void> gate = Completer<void>();
      final AuthController auth = AuthController(_ScriptedVerifier(gate: gate));

      final Future<bool> first = auth.submit('a1b2c3d4');
      expect(auth.isConnecting, isTrue);
      expect(auth.canSubmit('e5f6g7h8'), isFalse);
      expect(await auth.submit('e5f6g7h8'), isFalse);

      gate.complete();
      expect(await first, isTrue);
      expect(auth.attempts, 1);
    });

    test('editing the field clears the error', () async {
      final AuthController auth = AuthController(
        _ScriptedVerifier(failure: const SetupCodeRejectedException('nope')),
      );
      await auth.submit('a1b2c3d4');
      expect(auth.error, isNotNull);

      auth.clearError();
      expect(auth.error, isNull);
      expect(auth.stage, AuthStage.idle);
    });

    test('notifies on each stage change', () async {
      final AuthController auth = AuthController(_ScriptedVerifier());
      int notifications = 0;
      auth.addListener(() => notifications++);

      await auth.submit('a1b2c3d4');
      expect(notifications, 2); // connecting, then connected
    });
  });

  group('DemoSetupCodeVerifier', () {
    test('rejects the known-dead codes without a backend', () async {
      final DemoSetupCodeVerifier verifier = DemoSetupCodeVerifier(
        latency: Duration.zero,
      );
      await expectLater(
        verifier.verify('00000000'),
        throwsA(isA<SetupCodeRejectedException>()),
      );
    });

    test('accepts a plausible code', () async {
      final DemoSetupCodeVerifier verifier = DemoSetupCodeVerifier(
        latency: Duration.zero,
      );
      await expectLater(verifier.verify('wake-up-2026'), completes);
    });
  });
}
