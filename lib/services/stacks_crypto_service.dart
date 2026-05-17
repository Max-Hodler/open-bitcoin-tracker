import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_params.dart';

/// Encrypts/decrypts the user's stacks list and manages the wrapped DEK.
///
/// Design:
/// - A random 256-bit Data Encryption Key (DEK) encrypts the stacks JSON via
///   AES-256-GCM. The DEK lives in memory only while the user is unlocked.
/// - The DEK itself is wrapped (AES-256-GCM encrypted) under one or two Key
///   Encryption Keys: one derived from the user's PIN via Argon2id, and
///   optionally a second held in Android Keystore behind biometric auth.
/// - Wrapping the DEK separately means changing the PIN or toggling biometric
///   does not require re-encrypting the stacks blob — only the wrapper changes.
///
/// All persisted bytes are stored as base64 strings in [FlutterSecureStorage]
/// (which is itself Keystore-backed AES on Android — defense in depth).
/// Abstracts the bits of [BiometricStorage] we use, so unit tests can fake it
/// without a platform channel.
abstract class BiometricVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
  Future<bool> isAvailable();
}

class _BiometricStorageVault implements BiometricVault {
  _BiometricStorageVault();

  static const _slotName = 'stacks_dek_wrapped_bio';

  Future<BiometricStorageFile> _slot() => BiometricStorage().getStorage(
        _slotName,
        options: StorageFileInitOptions(
          authenticationRequired: true,
          androidBiometricOnly: true,
        ),
        promptInfo: const PromptInfo(
          androidPromptInfo: AndroidPromptInfo(
            title: 'Unlock stacks',
            negativeButton: 'Cancel',
          ),
        ),
      );

  @override
  Future<String?> read() async {
    final f = await _slot();
    return f.read();
  }

  @override
  Future<void> write(String value) async {
    final f = await _slot();
    await f.write(value);
  }

  @override
  Future<void> delete() async {
    final f = await _slot();
    await f.delete();
  }

  @override
  Future<bool> isAvailable() async {
    final r = await BiometricStorage().canAuthenticate();
    return r == CanAuthenticateResponse.success;
  }
}

class StacksCryptoService {
  StacksCryptoService({
    FlutterSecureStorage? storage,
    BiometricVault? biometricVault,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions:
                  AndroidOptions(encryptedSharedPreferences: true),
            ),
        _bio = biometricVault ?? _BiometricStorageVault();

  static const _kKdfSalt = 'stacks_crypto_kdf_salt';
  static const _kDekWrappedPin = 'stacks_crypto_dek_wrapped_pin';

  static final _argon2id = buildStacksArgon2id();

  static final _aes = AesGcm.with256bits();

  final FlutterSecureStorage _storage;
  final BiometricVault _bio;
  final Random _rng = Random.secure();

  /// Generate a fresh random 256-bit DEK. Public so the device-mode flow can
  /// mint a DEK without going through PIN derivation.
  List<int> newDek() => _randomBytes(32);

  /// True iff a PIN-wrapped DEK exists on disk.
  Future<bool> hasPinWrappedDek() async {
    final wrapped = await _storage.read(key: _kDekWrappedPin);
    final salt = await _storage.read(key: _kKdfSalt);
    return wrapped != null && salt != null;
  }

  /// First-time setup: generate a fresh DEK, derive a PIN KEK, wrap and
  /// persist. Returns the in-memory DEK so the caller can immediately encrypt
  /// the initial stacks blob in the same atomic transaction.
  Future<List<int>> initWithPin(String pin) async {
    final salt = _randomBytes(16);
    final dek = _randomBytes(32);
    final kek = await _deriveKek(pin, salt);
    final wrapped = await _wrap(dek, kek);
    await _storage.write(key: _kKdfSalt, value: base64.encode(salt));
    await _storage.write(key: _kDekWrappedPin, value: _encodeEnvelope(wrapped));
    return dek;
  }

  /// Returns the DEK if [pin] unwraps the stored DEK, or null on wrong PIN
  /// (or corrupt storage / missing data).
  Future<List<int>?> unwrapDekWithPin(String pin) async {
    final saltB64 = await _storage.read(key: _kKdfSalt);
    final wrappedStr = await _storage.read(key: _kDekWrappedPin);
    if (saltB64 == null || wrappedStr == null) return null;
    final salt = base64.decode(saltB64);
    final envelope = _decodeEnvelope(wrappedStr);
    if (envelope == null) return null;
    final kek = await _deriveKek(pin, salt);
    return _unwrap(envelope, kek);
  }

  /// Rewrap the same DEK under a new PIN. Used by Change PIN flows so the
  /// existing stacks blob doesn't need to be re-encrypted.
  Future<void> rewrapPin(List<int> dek, String newPin) async {
    final salt = _randomBytes(16);
    final kek = await _deriveKek(newPin, salt);
    final wrapped = await _wrap(dek, kek);
    await _storage.write(key: _kKdfSalt, value: base64.encode(salt));
    await _storage.write(key: _kDekWrappedPin, value: _encodeEnvelope(wrapped));
  }

  /// Wipe all wraps (PIN + biometric). Caller is responsible for also wiping
  /// the encrypted stacks blob from SharedPreferences.
  Future<void> wipeAllWraps() async {
    await removePinWrap();
    try {
      await _bio.delete();
    } on Object {
      // Best-effort. If the biometric slot doesn't exist or the platform
      // refuses, the PIN wipe above is what actually protects the data.
    }
  }

  /// Wipe only the PIN-derived wrap, leaving the biometric slot intact. Used
  /// by the pin → device mode transition once the biometric wrap is in place.
  Future<void> removePinWrap() async {
    await _storage.delete(key: _kKdfSalt);
    await _storage.delete(key: _kDekWrappedPin);
  }

  /// Persist the DEK in a biometric-bound Keystore slot. The OS will only
  /// release the bytes after a successful biometric auth.
  ///
  /// Returns true on success. Returns false if the platform refused — most
  /// commonly because no biometric is enrolled (Android Keystore requires
  /// at least one fingerprint to bind a key to user-auth-for-every-use),
  /// or because the user cancelled the prompt.
  Future<bool> addBiometricWrap(List<int> dek) async {
    try {
      await _bio.write(base64.encode(dek));
      return true;
    } on Object {
      // Common causes: no biometric enrolled, hardware unavailable, user
      // cancelled the prompt. Caller surfaces this to the user.
      return false;
    }
  }

  /// Returns the DEK after a successful biometric prompt, or null if the slot
  /// is missing (never enrolled, or invalidated by a fingerprint change —
  /// the underlying plugin silently deletes the slot in that case) or the
  /// user cancelled the prompt.
  Future<List<int>?> unwrapDekWithBiometric() async {
    try {
      final s = await _bio.read();
      if (s == null) return null;
      return base64.decode(s);
    } on AuthException {
      // User cancelled, prompt timed out, etc. Treat as "no unlock".
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> removeBiometricWrap() async {
    try {
      await _bio.delete();
    } on Object {
      // Slot may not exist; that's fine.
    }
  }

  /// Encrypt arbitrary UTF-8 string under the DEK and return a single
  /// base64 envelope suitable for storage. Used for the stacks blob.
  Future<String> encryptString(String plaintext, List<int> dek) async {
    final envelope = await _wrap(utf8.encode(plaintext), dek);
    return _encodeEnvelope(envelope);
  }

  /// Decrypt an envelope produced by [encryptString]. Returns null on MAC
  /// failure or malformed input.
  Future<String?> decryptString(String envelopeStr, List<int> dek) async {
    final envelope = _decodeEnvelope(envelopeStr);
    if (envelope == null) return null;
    final bytes = await _unwrap(envelope, dek);
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: false);
  }

  // --- internal ---

  Future<List<int>> _deriveKek(String pin, List<int> salt) async {
    final derived = await _argon2id.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return derived.extractBytes();
  }

  Future<_Envelope> _wrap(List<int> plaintext, List<int> key) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(key),
    );
    return _Envelope(
      nonce: box.nonce,
      ciphertext: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  Future<List<int>?> _unwrap(_Envelope env, List<int> key) async {
    try {
      return await _aes.decrypt(
        SecretBox(env.ciphertext, nonce: env.nonce, mac: Mac(env.mac)),
        secretKey: SecretKey(key),
      );
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  Uint8List _randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  // Envelope encoding: a single base64 string of a JSON object with three
  // base64 fields. Compact, self-describing, and survives any future format
  // bumps via an explicit version field.
  String _encodeEnvelope(_Envelope e) => base64.encode(utf8.encode(jsonEncode({
        'v': 1,
        'n': base64.encode(e.nonce),
        'c': base64.encode(e.ciphertext),
        'm': base64.encode(e.mac),
      })));

  _Envelope? _decodeEnvelope(String s) {
    try {
      final json = jsonDecode(utf8.decode(base64.decode(s)));
      if (json is! Map<String, dynamic>) return null;
      if (json['v'] != 1) return null;
      return _Envelope(
        nonce: base64.decode(json['n'] as String),
        ciphertext: base64.decode(json['c'] as String),
        mac: base64.decode(json['m'] as String),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class _Envelope {
  _Envelope({required this.nonce, required this.ciphertext, required this.mac});
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> mac;
}
