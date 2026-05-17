import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/stacks_crypto_service.dart';
import 'app_state.dart';
import 'stack.dart';

/// On-disk shape:
/// - Pre-encryption (legacy): `{stacks: [...], currency: ..., ...}` — stacks
///   field is a plaintext JSON list.
/// - Post-encryption: `{stacksEnc: "<base64 envelope>", currency: ..., ...}`
///   — `stacks` field is absent, `stacksEnc` carries an AES-GCM envelope from
///   [StacksCryptoService.encryptString] over a JSON list of stacks.
///
/// The repository owns the lifecycle of the ciphertext between load and save:
/// it remembers the envelope it loaded, and re-emits it unchanged whenever
/// the caller saves without providing a DEK (e.g. settings change while the
/// stacks are locked). Without that, a settings save while locked would write
/// `stacksEnc: null` and silently destroy the user's stacks.
class AppStateRepository {
  AppStateRepository(this._prefs, {StacksCryptoService? crypto})
      : _crypto = crypto ?? StacksCryptoService();

  static const String storageKey = 'btc_tracker';

  final SharedPreferences _prefs;
  final StacksCryptoService _crypto;
  String? _lastStacksEnc;

  /// True iff the most-recently-loaded blob carried encrypted stacks. Callers
  /// that boot the lock screen rely on this to decide whether to gate the UI.
  bool get hasEncryptedStacks => _lastStacksEnc != null;

  AppState load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      _lastStacksEnc = null;
      return const AppState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _lastStacksEnc = decoded['stacksEnc'] as String?;
        return AppState.fromJson(decoded);
      }
    } on FormatException {
      // Malformed blob — treat as first launch.
    }
    _lastStacksEnc = null;
    return const AppState();
  }

  /// Save the state.
  ///
  /// - If [dek] is provided, the in-memory [AppState.stacks] are encrypted
  ///   under it and written as `stacksEnc`; the cached envelope is updated.
  /// - If [dek] is null and the repository previously loaded an envelope
  ///   ([hasEncryptedStacks] is true), the envelope is re-emitted unchanged.
  ///   This is the locked-mode settings-write path.
  /// - If [dek] is null and there's no envelope, the legacy plaintext
  ///   `stacks` field is written. This is today's behavior, preserved for
  ///   users who haven't enabled the lock yet.
  Future<void> save(AppState state, {List<int>? dek}) async {
    final json = state.toJson();

    if (dek != null) {
      final stacksJson = jsonEncode(state.stacks.map((s) => s.toJson()).toList());
      _lastStacksEnc = await _crypto.encryptString(stacksJson, dek);
      json.remove('stacks');
      json['stacksEnc'] = _lastStacksEnc;
    } else if (_lastStacksEnc != null) {
      json.remove('stacks');
      json['stacksEnc'] = _lastStacksEnc;
    }
    // else: legacy plaintext path — leave json['stacks'] as-is.

    await _prefs.setString(storageKey, jsonEncode(json));
  }

  /// Decrypt the cached envelope using [dek] and return the resulting stacks.
  /// Returns null on MAC failure or absent envelope.
  Future<List<Stack>?> decryptStacks(List<int> dek) async {
    final env = _lastStacksEnc;
    if (env == null) return null;
    final json = await _crypto.decryptString(env, dek);
    if (json == null) return null;
    try {
      final list = jsonDecode(json);
      if (list is! List) return null;
      return list
          .map((e) => e is Map<String, dynamic> ? Stack.fromJson(e) : null)
          .whereType<Stack>()
          .toList();
    } on FormatException {
      return null;
    }
  }

  /// Drop the in-memory envelope cache. Used when the user disables the lock
  /// (decrypt-back path) and the next save must emit plaintext `stacks` again.
  void clearEncryptedStacks() {
    _lastStacksEnc = null;
  }
}
