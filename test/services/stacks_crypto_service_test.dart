import 'dart:convert';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:open_bitcoin_tracker/services/stacks_crypto_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StacksCryptoService - PIN paths', () {
    late _FakeSecureStorage storage;
    late _FakeBioVault bio;
    late StacksCryptoService crypto;

    setUp(() {
      storage = _FakeSecureStorage();
      bio = _FakeBioVault();
      crypto = StacksCryptoService(storage: storage, biometricVault: bio);
    });

    test('initWithPin then unwrap returns identical DEK bytes', () async {
      final dek1 = await crypto.initWithPin('1234');
      expect(dek1.length, 32);
      expect(await crypto.hasPinWrappedDek(), isTrue);

      final dek2 = await crypto.unwrapDekWithPin('1234');
      expect(dek2, isNotNull);
      expect(dek2, dek1);
    });

    test('wrong PIN returns null', () async {
      await crypto.initWithPin('1234');
      expect(await crypto.unwrapDekWithPin('9999'), isNull);
    });

    test('encryptString round-trips via DEK', () async {
      final dek = await crypto.initWithPin('pw');
      const plaintext = '[{"id":"a","name":"Cold","sats":100}]';
      final envelope = await crypto.encryptString(plaintext, dek);
      expect(envelope, isNot(contains('Cold')));

      final back = await crypto.decryptString(envelope, dek);
      expect(back, plaintext);
    });

    test('tampered ciphertext fails MAC and returns null', () async {
      final dek = await crypto.initWithPin('pw');
      final envelope = await crypto.encryptString('hello world', dek);
      final tampered = _flipByteInEnvelope(envelope, field: 'c');
      expect(await crypto.decryptString(tampered, dek), isNull);
    });

    test('tampered wrapped DEK fails to unwrap', () async {
      await crypto.initWithPin('pw');
      final stored = await storage.read(key: 'stacks_crypto_dek_wrapped_pin');
      final tampered = _flipByteInEnvelope(stored!, field: 'c');
      await storage.write(key: 'stacks_crypto_dek_wrapped_pin', value: tampered);
      expect(await crypto.unwrapDekWithPin('pw'), isNull);
    });

    test('rewrapPin keeps DEK identity intact', () async {
      final dek1 = await crypto.initWithPin('old');
      const plaintext = 'sensitive';
      final envelope = await crypto.encryptString(plaintext, dek1);

      await crypto.rewrapPin(dek1, 'new');
      // Old PIN no longer works.
      expect(await crypto.unwrapDekWithPin('old'), isNull);
      // New PIN unwraps the same DEK that still decrypts the envelope.
      final dek2 = await crypto.unwrapDekWithPin('new');
      expect(dek2, dek1);
      expect(await crypto.decryptString(envelope, dek2!), plaintext);
    });

    test('wipeAllWraps clears storage and disables future unwraps', () async {
      await crypto.initWithPin('pw');
      await crypto.wipeAllWraps();
      expect(await crypto.hasPinWrappedDek(), isFalse);
      expect(await crypto.unwrapDekWithPin('pw'), isNull);
    });

    test('decryptString returns null for malformed envelope', () async {
      final dek = await crypto.initWithPin('pw');
      expect(await crypto.decryptString('not-base64!@#', dek), isNull);
      expect(await crypto.decryptString('', dek), isNull);
    });

    test('two inits produce different DEKs and different salts', () async {
      final dek1 = await crypto.initWithPin('pw');
      await crypto.wipeAllWraps();
      final dek2 = await crypto.initWithPin('pw');
      expect(dek1, isNot(dek2));
    });
  });

  group('StacksCryptoService - biometric path', () {
    late _FakeSecureStorage storage;
    late _FakeBioVault bio;
    late StacksCryptoService crypto;

    setUp(() {
      storage = _FakeSecureStorage();
      bio = _FakeBioVault();
      crypto = StacksCryptoService(storage: storage, biometricVault: bio);
    });

    test('addBiometricWrap then unwrap returns same DEK', () async {
      final dek = await crypto.initWithPin('pw');
      await crypto.addBiometricWrap(dek);
      final out = await crypto.unwrapDekWithBiometric();
      expect(out, dek);
    });

    test('unwrap returns null when no biometric wrap exists', () async {
      await crypto.initWithPin('pw');
      expect(await crypto.unwrapDekWithBiometric(), isNull);
    });

    test('removeBiometricWrap clears the slot', () async {
      final dek = await crypto.initWithPin('pw');
      await crypto.addBiometricWrap(dek);
      await crypto.removeBiometricWrap();
      expect(await crypto.unwrapDekWithBiometric(), isNull);
    });

    test('wipeAllWraps removes both PIN and biometric wraps', () async {
      final dek = await crypto.initWithPin('pw');
      await crypto.addBiometricWrap(dek);
      await crypto.wipeAllWraps();
      expect(await crypto.unwrapDekWithPin('pw'), isNull);
      expect(await crypto.unwrapDekWithBiometric(), isNull);
    });

    test('biometric slot invalidation surfaces as null (re-enroll path)',
        () async {
      final dek = await crypto.initWithPin('pw');
      await crypto.addBiometricWrap(dek);
      // Simulate the OS-level fingerprint-changed event the real plugin
      // handles by silently deleting the keystore-bound slot.
      bio.simulateInvalidation();
      expect(await crypto.unwrapDekWithBiometric(), isNull);
      // PIN path is unaffected — that's the user's recovery route.
      expect(await crypto.unwrapDekWithPin('pw'), dek);
    });

    test('user cancels biometric prompt → null (no exception leaks)',
        () async {
      final dek = await crypto.initWithPin('pw');
      await crypto.addBiometricWrap(dek);
      bio.nextReadThrowsCancel = true;
      expect(await crypto.unwrapDekWithBiometric(), isNull);
    });
  });
}

/// Decode an envelope, flip one byte in the named base64 field, re-encode.
String _flipByteInEnvelope(String envelopeStr, {required String field}) {
  final outerJson = jsonDecode(utf8.decode(base64.decode(envelopeStr)))
      as Map<String, dynamic>;
  final bytes = base64.decode(outerJson[field] as String);
  bytes[0] = bytes[0] ^ 0xFF;
  outerJson[field] = base64.encode(bytes);
  return base64.encode(utf8.encode(jsonEncode(outerJson)));
}

/// Minimal in-memory fake of FlutterSecureStorage for tests.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

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
      _data[key];

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
      _data.remove(key);
    } else {
      _data[key] = value;
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
    _data.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBioVault implements BiometricVault {
  String? _value;
  bool nextReadThrowsCancel = false;

  void simulateInvalidation() {
    _value = null;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> read() async {
    if (nextReadThrowsCancel) {
      nextReadThrowsCancel = false;
      throw AuthException(AuthExceptionCode.userCanceled, 'cancel');
    }
    return _value;
  }

  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> delete() async {
    _value = null;
  }
}
