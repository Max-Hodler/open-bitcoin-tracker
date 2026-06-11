import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_bitcoin_tracker/services/crypto_params.dart';
import 'package:open_bitcoin_tracker/services/stacks_auth_service.dart';

/// In-memory stand-in for secure storage; only the members the auth service
/// uses are implemented.
class _MemStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> map = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      map[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    map.remove(key);
  }
}

void main() {
  group('cooldownFor ladder', () {
    test('no cooldown below the threshold', () {
      for (var i = 0; i < StacksAuthService.kFailuresBeforeCooldown; i++) {
        expect(StacksAuthService.cooldownFor(i), isNull);
      }
    });

    test('escalates 30s / 1m / 5m / 15m then caps at 1h', () {
      expect(StacksAuthService.cooldownFor(5), const Duration(seconds: 30));
      expect(StacksAuthService.cooldownFor(6), const Duration(minutes: 1));
      expect(StacksAuthService.cooldownFor(7), const Duration(minutes: 5));
      expect(StacksAuthService.cooldownFor(8), const Duration(minutes: 15));
      expect(StacksAuthService.cooldownFor(9), const Duration(hours: 1));
      expect(StacksAuthService.cooldownFor(100), const Duration(hours: 1));
    });
  });

  group('registerFailure / getRemainingCooldown', () {
    late _MemStorage storage;
    int? elapsedNow;

    StacksAuthService service() => StacksAuthService(
          storage: storage,
          elapsedRealtimeMs: () async => elapsedNow,
        );

    setUp(() {
      storage = _MemStorage();
      elapsedNow = 1000000;
    });

    Future<void> failTimes(StacksAuthService s, int n) async {
      for (var i = 0; i < n; i++) {
        await s.registerFailure();
      }
    }

    test('no cooldown before the fifth failure', () async {
      final s = service();
      await failTimes(s, 4);
      expect(await s.getRemainingCooldown(), isNull);
      expect(await s.getFailureCount(), 4);
    });

    test('fifth failure starts a ~30s cooldown', () async {
      final s = service();
      await failTimes(s, 5);
      final remaining = await s.getRemainingCooldown();
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, inInclusiveRange(28, 30));
    });

    test('monotonic anchor enforces cooldown when wall clock is rolled '
        'forward', () async {
      final s = service();
      await failTimes(s, 5);
      // Simulate the user rolling the device clock an hour forward: the
      // persisted wall-clock deadline is now in the past.
      storage.map['stacks_auth_cooldown_until'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      // Only 10 monotonic seconds have actually passed.
      elapsedNow = elapsedNow! + 10000;
      final remaining = await s.getRemainingCooldown();
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, inInclusiveRange(18, 20));
    });

    test('monotonic cooldown expires after the duration actually elapses',
        () async {
      final s = service();
      await failTimes(s, 5);
      elapsedNow = elapsedNow! + 31000;
      // Wall deadline also rolled past (clock untouched, 31s later is
      // simulated by rewriting the stored deadline).
      storage.map['stacks_auth_cooldown_until'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      expect(await s.getRemainingCooldown(), isNull);
    });

    test('reboot (monotonic clock reset) falls back to the wall clock',
        () async {
      final s = service();
      await failTimes(s, 5);
      // After reboot elapsedRealtime restarts near zero, below the anchor.
      elapsedNow = 5;
      final remaining = await s.getRemainingCooldown();
      // Wall deadline still applies.
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, inInclusiveRange(28, 30));
    });

    test('without a monotonic source behavior matches wall clock only',
        () async {
      elapsedNow = null;
      final s = service();
      await failTimes(s, 5);
      expect(storage.map.containsKey('stacks_auth_cooldown_anchor_elapsed'),
          isFalse);
      final remaining = await s.getRemainingCooldown();
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, inInclusiveRange(28, 30));
    });

    test('resetFailures clears the count, deadline, and monotonic anchor',
        () async {
      final s = service();
      await failTimes(s, 6);
      await s.resetFailures();
      expect(await s.getFailureCount(), 0);
      expect(await s.getRemainingCooldown(), isNull);
      expect(storage.map, isEmpty);
    });
  });

  group('setPin / verifyPin (worker-isolate Argon2id)', () {
    late _MemStorage storage;

    StacksAuthService service() => StacksAuthService(
          storage: storage,
          elapsedRealtimeMs: () async => 1000000,
        );

    setUp(() {
      storage = _MemStorage();
    });

    test('setPin then verifyPin round-trips; wrong PIN rejected', () async {
      final s = service();
      await s.setPin('1234');
      expect(await s.verifyPin('1234'), isTrue);
      expect(await s.verifyPin('4321'), isFalse);
    });

    // The hash moved onto a worker isolate (compute) for unlock latency.
    // A hash written directly with the shared primitives — byte-identical
    // to what the pre-isolate code persisted — must still verify, or
    // existing users would be locked out by the refactor.
    test('PIN hash written by the old main-isolate code still verifies',
        () async {
      final salt = List<int>.generate(16, (i) => (i * 13) % 256);
      final derived = await buildStacksArgon2id().deriveKey(
        secretKey: SecretKey(utf8.encode('1234')),
        nonce: salt,
      );
      storage.map['stacks_auth_pin_hash'] =
          base64.encode(await derived.extractBytes());
      storage.map['stacks_auth_pin_salt'] = base64.encode(salt);

      final s = service();
      expect(await s.verifyPin('1234'), isTrue);
      expect(await s.verifyPin('4321'), isFalse);
    });
  });
}
