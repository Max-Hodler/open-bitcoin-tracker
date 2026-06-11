import 'dart:convert';
import 'dart:math';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
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

// ---------------------------------------------------------------------------
// Top-level compute() entrypoints — must be top-level (not closures or
// instance methods) so the isolate spawner can reference them by address.
// Only plain-data types cross isolate boundaries here: List<int>, String.
// No platform-channel handles (FlutterSecureStorage, BiometricVault) leak in.
// ---------------------------------------------------------------------------

/// Argon2id KEK derivation + AES-GCM wrap in one isolate hop.
/// Returns the encoded envelope string.
Future<String> _deriveAndWrap(_DeriveAndWrapArgs args) async {
  final argon2id = buildStacksArgon2id();
  final aes = AesGcm.with256bits();
  final derived = await argon2id.deriveKey(
    secretKey: SecretKey(args.pinBytes),
    nonce: args.salt,
  );
  final kekBytes = await derived.extractBytes();
  final box = await aes.encrypt(
    args.plaintext,
    secretKey: SecretKey(kekBytes),
  );
  return _encodeEnvelopeStatic(_EnvelopeData(
    nonce: box.nonce,
    ciphertext: box.cipherText,
    mac: box.mac.bytes,
  ));
}

/// Argon2id KEK derivation + AES-GCM unwrap in one isolate hop.
/// Returns the decrypted bytes, or null on MAC failure or wrong PIN.
Future<List<int>?> _deriveAndUnwrap(_DeriveAndUnwrapArgs args) async {
  final argon2id = buildStacksArgon2id();
  final aes = AesGcm.with256bits();
  final derived = await argon2id.deriveKey(
    secretKey: SecretKey(args.pinBytes),
    nonce: args.salt,
  );
  final kekBytes = await derived.extractBytes();
  try {
    return await aes.decrypt(
      SecretBox(args.ciphertext, nonce: args.nonce, mac: Mac(args.mac)),
      secretKey: SecretKey(kekBytes),
    );
  } on SecretBoxAuthenticationError {
    return null;
  }
}

/// AES-GCM encrypt in one isolate hop (no KDF — key already in memory).
/// Returns the encoded envelope string.
Future<String> _aesEncrypt(_AesArgs args) async {
  final aes = AesGcm.with256bits();
  final box = await aes.encrypt(
    args.plaintext,
    secretKey: SecretKey(args.key),
  );
  return _encodeEnvelopeStatic(_EnvelopeData(
    nonce: box.nonce,
    ciphertext: box.cipherText,
    mac: box.mac.bytes,
  ));
}

/// AES-GCM decrypt in one isolate hop (no KDF — key already in memory).
/// Returns the decrypted bytes, or null on MAC failure.
Future<List<int>?> _aesDecrypt(_AesDecryptArgs args) async {
  final aes = AesGcm.with256bits();
  try {
    return await aes.decrypt(
      SecretBox(args.ciphertext, nonce: args.nonce, mac: Mac(args.mac)),
      secretKey: SecretKey(args.key),
    );
  } on SecretBoxAuthenticationError {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Plain-data argument structs for compute() — all fields are List<int>/String,
// which the isolate message-passing mechanism can copy without issue.
// ---------------------------------------------------------------------------

class _DeriveAndWrapArgs {
  const _DeriveAndWrapArgs({
    required this.pinBytes,
    required this.salt,
    required this.plaintext,
  });
  final List<int> pinBytes;
  final List<int> salt;
  final List<int> plaintext;
}

class _DeriveAndUnwrapArgs {
  const _DeriveAndUnwrapArgs({
    required this.pinBytes,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });
  final List<int> pinBytes;
  final List<int> salt;
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> mac;
}

class _AesArgs {
  const _AesArgs({
    required this.plaintext,
    required this.key,
  });
  final List<int> plaintext;
  final List<int> key;
}

class _AesDecryptArgs {
  const _AesDecryptArgs({
    required this.key,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });
  final List<int> key;
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> mac;
}

// ---------------------------------------------------------------------------
// Envelope codec — shared between main isolate and worker isolates via the
// static helpers below.
// ---------------------------------------------------------------------------

class _EnvelopeData {
  _EnvelopeData({required this.nonce, required this.ciphertext, required this.mac});
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> mac;
}

String _encodeEnvelopeStatic(_EnvelopeData e) =>
    base64.encode(utf8.encode(jsonEncode({
      'v': 1,
      'n': base64.encode(e.nonce),
      'c': base64.encode(e.ciphertext),
      'm': base64.encode(e.mac),
    })));

_EnvelopeData? _decodeEnvelopeStatic(String s) {
  try {
    final json = jsonDecode(utf8.decode(base64.decode(s)));
    if (json is! Map<String, dynamic>) return null;
    if (json['v'] != 1) return null;
    return _EnvelopeData(
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

// ---------------------------------------------------------------------------

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
    // Argon2id + AES-GCM on a worker isolate so the PIN screen stays live.
    final wrapped = await compute(
      _deriveAndWrap,
      _DeriveAndWrapArgs(
        pinBytes: utf8.encode(pin),
        salt: salt,
        plaintext: dek,
      ),
    );
    await _storage.write(key: _kKdfSalt, value: base64.encode(salt));
    await _storage.write(key: _kDekWrappedPin, value: wrapped);
    return dek;
  }

  /// Returns the DEK if [pin] unwraps the stored DEK, or null on wrong PIN
  /// (or corrupt storage / missing data).
  Future<List<int>?> unwrapDekWithPin(String pin) async {
    // Read plain data on the main isolate (storage handles can't cross).
    final saltB64 = await _storage.read(key: _kKdfSalt);
    final wrappedStr = await _storage.read(key: _kDekWrappedPin);
    if (saltB64 == null || wrappedStr == null) return null;
    final salt = base64.decode(saltB64);
    final envelope = _decodeEnvelopeStatic(wrappedStr);
    if (envelope == null) return null;
    // Argon2id + AES-GCM on a worker isolate — keeps the PIN screen responsive.
    return compute(
      _deriveAndUnwrap,
      _DeriveAndUnwrapArgs(
        pinBytes: utf8.encode(pin),
        salt: salt,
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
        mac: envelope.mac,
      ),
    );
  }

  /// Rewrap the same DEK under a new PIN. Used by Change PIN flows so the
  /// existing stacks blob doesn't need to be re-encrypted.
  Future<void> rewrapPin(List<int> dek, String newPin) async {
    final salt = _randomBytes(16);
    final wrapped = await compute(
      _deriveAndWrap,
      _DeriveAndWrapArgs(
        pinBytes: utf8.encode(newPin),
        salt: salt,
        plaintext: dek,
      ),
    );
    await _storage.write(key: _kKdfSalt, value: base64.encode(salt));
    await _storage.write(key: _kDekWrappedPin, value: wrapped);
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
    return compute(
      _aesEncrypt,
      _AesArgs(plaintext: utf8.encode(plaintext), key: dek),
    );
  }

  /// Decrypt an envelope produced by [encryptString]. Returns null on MAC
  /// failure or malformed input.
  Future<String?> decryptString(String envelopeStr, List<int> dek) async {
    final envelope = _decodeEnvelopeStatic(envelopeStr);
    if (envelope == null) return null;
    final bytes = await compute(
      _aesDecrypt,
      _AesDecryptArgs(
        key: dek,
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
        mac: envelope.mac,
      ),
    );
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: false);
  }

  // --- internal ---

  Uint8List _randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }
}
