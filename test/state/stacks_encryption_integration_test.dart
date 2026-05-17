import 'dart:convert';

import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/services/stacks_crypto_service.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end style tests against the real notifier + repository + crypto
/// stack, with platform plugins faked. These exercise the migration path,
/// lock/unlock cycles, and recovery from interrupted migrations — the parts
/// the unit tests for [StacksCryptoService] alone cannot cover.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_Harness> build({Map<String, Object> initialPrefs = const {}}) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final secure = _FakeSecureStorage();
    final bio = _FakeBioVault();
    final crypto = StacksCryptoService(storage: secure, biometricVault: bio);
    final repo = AppStateRepository(prefs, crypto: crypto);
    final notifier = AppStateNotifier(repo);
    return _Harness(prefs, secure, bio, crypto, repo, notifier);
  }

  group('first-time PIN setup migrates plaintext stacks to ciphertext', () {
    test('non-empty stacks: plaintext gone, ciphertext present', () async {
      final h = await build(initialPrefs: const {
        'btc_tracker':
            '{"currency":"USD","stacks":[{"id":"a","name":"Cold","sats":100}]}',
      });
      expect(h.notifier.stacks.length, 1);

      // Simulate the first-PIN setup flow.
      final dek = await h.crypto.initWithPin('1234');
      await h.notifier.adoptDek(dek);

      final raw = h.prefs.getString('btc_tracker')!;
      expect(raw, contains('stacksEnc'));
      expect(raw, isNot(contains('"stacks":[')));
      expect(raw, isNot(contains('Cold'))); // name not visible in ciphertext
    });

    test('empty stacks first-PIN setup yields no ciphertext for nothing',
        () async {
      final h = await build();
      expect(h.notifier.stacks, isEmpty);

      final dek = await h.crypto.initWithPin('pw');
      await h.notifier.adoptDek(dek);

      // After adopting an empty stacks list, the envelope encrypts an empty
      // JSON list — still produces a stacksEnc field, which is correct: the
      // user has now opted into encryption, even with zero stacks.
      final raw = h.prefs.getString('btc_tracker')!;
      expect(raw, contains('stacksEnc'));
    });
  });

  group('lock / unlock cycle', () {
    test('cold start with encrypted blob: notifier.stacks is empty until '
        'unlock', () async {
      // Pretend the user already migrated in a previous session. Manually
      // construct the on-disk state by running a setup once...
      final setup = await build(initialPrefs: const {
        'btc_tracker':
            '{"currency":"USD","stacks":[{"id":"a","name":"Cold","sats":100}]}',
      });
      final dek = await setup.crypto.initWithPin('1234');
      await setup.notifier.adoptDek(dek);
      final encryptedRaw = setup.prefs.getString('btc_tracker')!;
      final secureBackup = setup.secure.snapshot();

      // ...then simulate a fresh process: new prefs map seeded with the
      // encrypted blob, new secure storage seeded with the wraps.
      SharedPreferences.setMockInitialValues({'btc_tracker': encryptedRaw});
      final prefs = await SharedPreferences.getInstance();
      final secure = _FakeSecureStorage()..restore(secureBackup);
      final bio = _FakeBioVault();
      final crypto2 = StacksCryptoService(storage: secure, biometricVault: bio);
      final repo2 = AppStateRepository(prefs, crypto: crypto2);
      final notifier2 = AppStateNotifier(repo2);

      expect(notifier2.stacksEncryptedAtRest, isTrue);
      expect(notifier2.isUnlocked, isFalse);
      expect(notifier2.stacks, isEmpty);

      // Unlock with PIN.
      final dek2 = await crypto2.unwrapDekWithPin('1234');
      expect(dek2, isNotNull);
      final ok = await notifier2.unlockWithDek(dek2!);
      expect(ok, isTrue);
      expect(notifier2.stacks.length, 1);
      expect(notifier2.stacks.single.name, 'Cold');
    });

    test('relock clears in-memory stacks but leaves disk envelope', () async {
      final h = await build(initialPrefs: const {
        'btc_tracker':
            '{"currency":"USD","stacks":[{"id":"a","name":"Cold","sats":100}]}',
      });
      final dek = await h.crypto.initWithPin('pw');
      await h.notifier.adoptDek(dek);
      final encryptedRawBefore = h.prefs.getString('btc_tracker')!;

      h.notifier.relock();
      expect(h.notifier.stacks, isEmpty);
      expect(h.notifier.isUnlocked, isFalse);

      // Disk envelope is untouched.
      expect(h.prefs.getString('btc_tracker'), encryptedRawBefore);
    });

    test('settings save while locked re-emits envelope unchanged', () async {
      final h = await build(initialPrefs: const {
        'btc_tracker':
            '{"currency":"USD","stacks":[{"id":"a","name":"Cold","sats":100}]}',
      });
      final dek = await h.crypto.initWithPin('pw');
      await h.notifier.adoptDek(dek);
      final beforeBlob = jsonDecode(h.prefs.getString('btc_tracker')!)
          as Map<String, dynamic>;

      h.notifier.relock();
      h.notifier.setCurrency(Currency.eur);
      await Future<void>.delayed(Duration.zero);

      final afterBlob = jsonDecode(h.prefs.getString('btc_tracker')!)
          as Map<String, dynamic>;
      expect(afterBlob['currency'], 'EUR');
      expect(afterBlob['stacksEnc'], beforeBlob['stacksEnc']);
      expect(afterBlob.containsKey('stacks'), isFalse);
    });
  });

  group('PIN change preserves stacks', () {
    test('rewrap with new PIN, decrypt envelope on next unlock', () async {
      final h = await build(initialPrefs: const {
        'btc_tracker':
            '{"currency":"USD","stacks":[{"id":"a","name":"Cold","sats":100}]}',
      });
      final dek = await h.crypto.initWithPin('old');
      await h.notifier.adoptDek(dek);

      // Rewrap with new PIN (no need to touch the envelope).
      await h.crypto.rewrapPin(dek, 'new');

      // Unlock with new PIN succeeds, old PIN fails.
      expect(await h.crypto.unwrapDekWithPin('old'), isNull);
      final dek2 = await h.crypto.unwrapDekWithPin('new');
      expect(dek2, dek);

      h.notifier.relock();
      expect(await h.notifier.unlockWithDek(dek2!), isTrue);
      expect(h.notifier.stacks.single.name, 'Cold');
    });
  });

  group('disable-lock decrypt-back path', () {
    test('clearEncryptionAndSave returns blob to plaintext form', () async {
      final h = await build(initialPrefs: const {
        'btc_tracker':
            '{"currency":"USD","stacks":[{"id":"a","name":"Cold","sats":100}]}',
      });
      final dek = await h.crypto.initWithPin('pw');
      await h.notifier.adoptDek(dek);

      await h.notifier.clearEncryptionAndSave();
      // Crypto wraps must also be wiped by the caller — that's the auth
      // service's responsibility, but we can verify the prefs side.
      final raw = h.prefs.getString('btc_tracker')!;
      expect(raw, contains('"name":"Cold"'));
      expect(raw, isNot(contains('stacksEnc')));
    });
  });

  group('mid-migration crash recovery', () {
    test('orphan wrap with no envelope: PIN exists but stacks still '
        'plaintext', () async {
      // Simulate the order: initWithPin succeeded (wrap written), but the
      // adoptDek save was killed before SharedPreferences updated.
      SharedPreferences.setMockInitialValues(const {
        'btc_tracker':
            '{"currency":"USD","stacks":[{"id":"a","name":"Cold","sats":100}]}',
      });
      final prefs = await SharedPreferences.getInstance();
      final secure = _FakeSecureStorage();
      final bio = _FakeBioVault();
      final crypto = StacksCryptoService(storage: secure, biometricVault: bio);
      // Create the wrap as if a previous setup got that far.
      await crypto.initWithPin('1234');
      // SharedPreferences is still the pre-migration plaintext.

      final repo = AppStateRepository(prefs, crypto: crypto);
      final notifier = AppStateNotifier(repo);

      // Boot-time invariants: stacks readable, encryption considered NOT yet
      // active (no envelope on disk), wrap is orphaned.
      expect(notifier.stacks.length, 1);
      expect(notifier.stacksEncryptedAtRest, isFalse);
      expect(await crypto.hasPinWrappedDek(), isTrue);

      // The right behavior on boot is to wipe the orphan wrap so the user
      // can re-attempt setup. That reconciliation lives in the auth/lock
      // layer (next step). Here we just assert the data is recoverable.
    });
  });
}

class _Harness {
  _Harness(this.prefs, this.secure, this.bio, this.crypto, this.repo,
      this.notifier);
  final SharedPreferences prefs;
  final _FakeSecureStorage secure;
  final _FakeBioVault bio;
  final StacksCryptoService crypto;
  final AppStateRepository repo;
  final AppStateNotifier notifier;
}

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  Map<String, String> snapshot() => Map.of(_data);
  void restore(Map<String, String> from) {
    _data
      ..clear()
      ..addAll(from);
  }

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

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> delete() async {
    _value = null;
  }
}
