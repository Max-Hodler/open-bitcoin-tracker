import '../state/app_state_notifier.dart';
import 'stacks_auth_service.dart';
import 'stacks_crypto_service.dart';

/// Result of an unlock attempt.
enum UnlockOutcome {
  /// Stacks decrypted (or never were encrypted) and notifier updated.
  /// Caller should now flip the lock controller to unlocked.
  success,

  /// PIN was wrong, or biometric prompt was cancelled / no slot exists.
  /// Caller should let the screen show its retry UI.
  wrongCredential,

  /// Wrap exists but decrypting yielded a MAC failure (corrupt blob).
  /// Caller should escalate to the destructive "reset stacks lock" flow —
  /// the data is unrecoverable but the user can wipe and start over.
  corruptBlob,
}

/// Coordinates the unlock + lazy-migration flow across:
///   - [StacksAuthService] (PIN hash + cooldown)
///   - [StacksCryptoService] (DEK wraps + envelope)
///   - [AppStateNotifier] (in-memory state + persistence)
///
/// Lazy migration: existing users who set a PIN before encryption shipped
/// have a PIN hash but no DEK wrap and plaintext stacks. On their first
/// successful unlock after the update, we silently encrypt their data and
/// rewrap. They see no change in behavior, only the on-disk shape moves
/// from plaintext to ciphertext.
class StacksUnlockOrchestrator {
  StacksUnlockOrchestrator({
    required AppStateNotifier app,
    required StacksAuthService auth,
    required StacksCryptoService crypto,
  })  : _app = app,
        _auth = auth,
        _crypto = crypto;

  final AppStateNotifier _app;
  final StacksAuthService _auth;
  final StacksCryptoService _crypto;

  /// PIN-mode unlock. Tries the wrapped-DEK path first; falls back to the
  /// legacy PIN-hash verify if no wrap exists yet, and migrates on success.
  Future<UnlockOutcome> unlockWithPin(String pin) async {
    if (await _crypto.hasPinWrappedDek()) {
      final dek = await _crypto.unwrapDekWithPin(pin);
      if (dek == null) return UnlockOutcome.wrongCredential;
      // We have a DEK. If the stacks blob exists, decrypt; otherwise (the
      // edge case where setup wrote the wrap but not the envelope, or the
      // user has zero stacks and we never bothered writing one), just adopt.
      if (_app.stacksEncryptedAtRest) {
        final ok = await _app.unlockWithDek(dek);
        if (!ok) return UnlockOutcome.corruptBlob;
      } else {
        await _app.adoptDek(dek);
      }
      return UnlockOutcome.success;
    }
    // Legacy path: no DEK wrap yet. Verify against the existing PIN hash,
    // then perform the migration so the next unlock uses the wrapped path.
    final ok = await _auth.verifyPin(pin);
    if (!ok) return UnlockOutcome.wrongCredential;
    final dek = await _crypto.initWithPin(pin);
    await _app.adoptDek(dek);
    return UnlockOutcome.success;
  }

  /// Device-mode unlock. Tries the biometric Keystore wrap; if none exists
  /// (legacy device-mode user pre-encryption), we ask the OS to authenticate
  /// the user, then mint a fresh DEK and bind it to the biometric slot.
  Future<UnlockOutcome> unlockWithDevice() async {
    final dek = await _crypto.unwrapDekWithBiometric();
    if (dek != null) {
      if (_app.stacksEncryptedAtRest) {
        final ok = await _app.unlockWithDek(dek);
        if (!ok) return UnlockOutcome.corruptBlob;
      } else {
        await _app.adoptDek(dek);
      }
      return UnlockOutcome.success;
    }
    // No wrap. Could be: legacy device-mode user, OR user cancelled the
    // biometric prompt. We can't tell from null alone — but the biometric
    // path has its own UI for failed/cancelled prompts: if the OS prompt
    // succeeded we'd have bytes back. So treat null as "auth didn't happen".
    // The migration path for legacy device-mode users is handled by an
    // explicit migrateDeviceMode() call from the screen, which prompts
    // biometric ourselves and then writes the wrap.
    return UnlockOutcome.wrongCredential;
  }

  /// First-time setup or migration for device mode: prompt biometric via
  /// [StacksAuthService.authenticateDevice], then mint a DEK and persist
  /// it in the biometric Keystore slot.
  Future<UnlockOutcome> migrateOrInitDeviceMode() async {
    final ok = await _auth.authenticateDevice(
      reason: 'Confirm to enable device unlock',
    );
    if (!ok) return UnlockOutcome.wrongCredential;
    // Generate a DEK and bind it to the biometric slot. We do NOT create a
    // PIN wrap — device mode is biometric-only by design (matches the
    // existing UI, with the new at-rest property that data is bound to the
    // biometric keystore key).
    final dek = _crypto.newDek();
    final bound = await _crypto.addBiometricWrap(dek);
    if (!bound) return UnlockOutcome.wrongCredential;
    await _app.adoptDek(dek);
    return UnlockOutcome.success;
  }

  /// First-time setup or migration for PIN mode (used by the PIN setup
  /// screen — covers both new users and legacy users who had `stacksAuthMode
  /// = off` but are now setting a PIN for the first time).
  Future<List<int>> initPinMode(String pin) async {
    final dek = await _crypto.initWithPin(pin);
    await _app.adoptDek(dek);
    return dek;
  }

  /// Mode transition: the user is currently unlocked under PIN and wants to
  /// move to device. We add a biometric wrap of the same DEK, then drop the
  /// PIN wrap and the legacy auth-service PIN hash. Returns false if the
  /// caller doesn't currently hold a DEK in memory (the transition flow must
  /// re-auth first to populate it).
  Future<bool> switchPinToDevice(List<int> dek) async {
    final bound = await _crypto.addBiometricWrap(dek);
    if (!bound) return false;
    await _crypto.removePinWrap();
    await _auth.clearPin();
    return true;
  }

  /// Mode transition: the user is currently unlocked under device (biometric)
  /// and wants to move to PIN. We add a PIN wrap of the same DEK, persist the
  /// PIN hash for cooldown plumbing, then drop the biometric wrap.
  Future<void> switchDeviceToPin(List<int> dek, String newPin) async {
    await _crypto.rewrapPin(dek, newPin);
    await _auth.setPin(newPin);
    await _crypto.removeBiometricWrap();
  }

  /// Mode transition: any → off. Decrypts stacks back to plaintext on disk
  /// and wipes every wrap + PIN hash. Caller has already obtained the DEK
  /// via re-auth and called [AppStateNotifier.unlockWithDek].
  Future<void> switchToOff() async {
    await _app.clearEncryptionAndSave();
    await _crypto.wipeAllWraps();
    await _auth.clearPin();
  }

  /// Destructive reset: wipe wraps, wipe PIN hash, drop the encrypted blob,
  /// and clear stacks from memory. Used by "Reset stacks lock" (formerly
  /// "Forget PIN") and by the corrupt-blob recovery path.
  Future<void> resetEverything() async {
    await _crypto.wipeAllWraps();
    await _auth.clearPin();
    _app.clearStacks();
    await _app.clearEncryptionAndSave();
  }

}
