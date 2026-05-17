import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/hashrate_client.dart';
import '../data/data.dart';

class AppStateNotifier extends ChangeNotifier {
  AppStateNotifier(this._repo) : _state = _repo.load();

  final AppStateRepository _repo;
  AppState _state;
  // The data-encryption key, held only between unlock and re-lock. Null means
  // the stacks are either not encrypted at all (legacy) or the user is
  // currently locked. Mutations to `stacks` while this is null and the repo
  // has an envelope are a programming error — the UI must be gated.
  List<int>? _dek;

  AppState get state => _state;

  /// True iff the on-disk stacks blob is an encrypted envelope (the user has
  /// gone through PIN setup at least once).
  bool get stacksEncryptedAtRest => _repo.hasEncryptedStacks;

  /// True iff the in-memory DEK is currently held — i.e. the user is unlocked.
  bool get isUnlocked => _dek != null || !_repo.hasEncryptedStacks;

  /// Read-only view of the in-memory DEK. Intended for the unlock orchestrator
  /// during mode transitions, where the same DEK needs to be re-wrapped under
  /// a different KEK. Callers must not retain the bytes beyond the immediate
  /// operation.
  List<int>? get currentDek => _dek;

  List<Stack> get stacks => _state.stacks;
  Currency get currency => _state.currency;
  List<Currency> get selectedCurrencies => _state.selectedCurrencies;
  bool get showPortfolio => _state.showPortfolio;
  bool get totalCardAtBottom => _state.totalCardAtBottom;
  bool get showConverterButton => _state.showConverterButton;
  bool get showMempool => _state.showMempool;
  bool get showHashrate => _state.showHashrate;
  bool get showChart => _state.showChart;
  bool get showBtcPrice => _state.showBtcPrice;
  AppTheme get theme => _state.theme;
  DarkVariant get darkVariant => _state.darkVariant;
  LightVariant get lightVariant => _state.lightVariant;
  BtcRange get btcRange => _state.btcRange;
  BtcRange get overflowQuickRange => _state.overflowQuickRange;
  BtcRange get monthsOverflowQuickRange => _state.monthsOverflowQuickRange;
  HashrateRange get hashrateRange => _state.hashrateRange;
  bool get logScale => _state.logScale;
  BtcDisplayMode get bitcoinDisplayMode => _state.bitcoinDisplayMode;
  StacksAuthMode get stacksAuthMode => _state.stacksAuthMode;
  StacksLockTimeout get stacksLockTimeout => _state.stacksLockTimeout;
  LanguagePref get language => _state.language;
  LivePriceCadence get livePriceCadence => _state.livePriceCadence;
  Currency? get converterCurrency => _state.converterCurrency;
  BtcDisplayMode? get converterBtcMode => _state.converterBtcMode;
  String? get converterMode => _state.converterMode;
  String? get converterFiatModeRaw => _state.converterFiatModeRaw;
  String? get converterFiatModeActiveSlot => _state.converterFiatModeActiveSlot;
  String? get converterSatsModeRaw => _state.converterSatsModeRaw;
  String? get converterSatsModeActiveSlot => _state.converterSatsModeActiveSlot;
  List<HomeWidget> get homeWidgetOrder => _state.homeWidgetOrder;

  void setCurrency(Currency value) => _update((s) => s.copyWith(currency: value));

  /// Persists the converter screen's local fiat currency. Independent from
  /// [setCurrency] — does NOT touch the home-screen currency or the swipe
  /// ring. The converter screen calls this on first build (seeding from
  /// [currency]) and from its picker.
  void setConverterCurrency(Currency value) =>
      _update((s) => s.copyWith(converterCurrency: value));

  /// Persists the converter screen's local Bitcoin display unit. Independent
  /// from [setBitcoinDisplayMode] — the global setting that drives every
  /// other amount readout in the app stays untouched.
  void setConverterBtcMode(BtcDisplayMode value) =>
      _update((s) => s.copyWith(converterBtcMode: value));

  /// Persists the converter's mode toggle (fiat↔BTC vs sats↔BTC).
  void setConverterMode(String value) =>
      _update((s) => s.copyWith(converterMode: value));

  /// Persists the per-mode raw input + active slot for the converter screen
  /// so values survive app restarts. Called on every keystroke; the [_update]
  /// path is cheap enough at human typing speed.
  void setConverterFiatModeEntry({
    required String raw,
    required String activeSlot,
  }) =>
      _update((s) => s.copyWith(
            converterFiatModeRaw: raw,
            converterFiatModeActiveSlot: activeSlot,
          ));
  void setConverterSatsModeEntry({
    required String raw,
    required String activeSlot,
  }) =>
      _update((s) => s.copyWith(
            converterSatsModeRaw: raw,
            converterSatsModeActiveSlot: activeSlot,
          ));

  /// Replace the user's picked currencies. Order matters — it's the order the
  /// home-screen swipe gesture cycles through. The list is normalized to 1–3
  /// unique entries; if the currently displayed currency isn't in [next], the
  /// active currency snaps to the first entry.
  void setSelectedCurrencies(List<Currency> next) {
    final unique = <Currency>[];
    for (final c in next) {
      if (!unique.contains(c)) unique.add(c);
      if (unique.length == 3) break;
    }
    if (unique.isEmpty) return;
    final shouldSnap = !unique.contains(_state.currency);
    _update((s) => s.copyWith(
          selectedCurrencies: unique,
          currency: shouldSnap ? unique.first : s.currency,
        ));
  }
  void setShowPortfolio(bool value) => _update((s) => s.copyWith(showPortfolio: value));
  void setTotalCardAtBottom(bool value) => _update((s) => s.copyWith(totalCardAtBottom: value));
  void setShowConverterButton(bool value) => _update((s) => s.copyWith(showConverterButton: value));
  void setShowMempool(bool value) => _update((s) => s.copyWith(showMempool: value));
  void setShowHashrate(bool value) => _update((s) => s.copyWith(showHashrate: value));
  void setShowChart(bool value) => _update((s) => s.copyWith(showChart: value));
  void setShowBtcPrice(bool value) => _update((s) => s.copyWith(showBtcPrice: value));
  void setTheme(AppTheme value) => _update((s) => s.copyWith(theme: value));
  void setDarkVariant(DarkVariant value) =>
      _update((s) => s.copyWith(darkVariant: value));
  void setLightVariant(LightVariant value) =>
      _update((s) => s.copyWith(lightVariant: value));
  void setBtcRange(BtcRange value) => _update((s) => s.copyWith(btcRange: value));
  void setOverflowQuickRange(BtcRange value) =>
      _update((s) => s.copyWith(overflowQuickRange: value));
  void setMonthsOverflowQuickRange(BtcRange value) =>
      _update((s) => s.copyWith(monthsOverflowQuickRange: value));
  void setHashrateRange(HashrateRange value) =>
      _update((s) => s.copyWith(hashrateRange: value));
  void setLogScale(bool value) => _update((s) => s.copyWith(logScale: value));
  void setBitcoinDisplayMode(BtcDisplayMode value) =>
      _update((s) => s.copyWith(bitcoinDisplayMode: value));
  void setStacksAuthMode(StacksAuthMode value) =>
      _update((s) => s.copyWith(stacksAuthMode: value));
  void setStacksLockTimeout(StacksLockTimeout value) =>
      _update((s) => s.copyWith(stacksLockTimeout: value));
  void setLanguage(LanguagePref value) =>
      _update((s) => s.copyWith(language: value));
  void setLivePriceCadence(LivePriceCadence value) =>
      _update((s) => s.copyWith(livePriceCadence: value));

  void addStack(Stack stack) =>
      _update((s) => s.copyWith(stacks: [...s.stacks, stack]));

  void updateStack(String id, Stack Function(Stack) mutate) {
    _update((s) => s.copyWith(
          stacks: [
            for (final stack in s.stacks)
              if (stack.id == id) mutate(stack) else stack,
          ],
        ));
  }

  void removeStack(String id) {
    _update((s) => s.copyWith(
          stacks: s.stacks.where((stack) => stack.id != id).toList(),
        ));
  }

  void clearStacks() {
    _update((s) => s.copyWith(stacks: const []));
  }

  void resetSettings() {
    _update((s) => const AppState().copyWith(
          stacks: s.stacks,
          stacksAuthMode: s.stacksAuthMode,
          stacksLockTimeout: s.stacksLockTimeout,
          language: s.language,
        ));
  }

  void reorderStacks(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    _update((s) {
      final next = [...s.stacks];
      final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
      final moved = next.removeAt(oldIndex);
      next.insert(adjusted, moved);
      return s.copyWith(stacks: next);
    });
  }

  void reorderHomeWidgets(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    _update((s) {
      final next = [...s.homeWidgetOrder];
      final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
      final moved = next.removeAt(oldIndex);
      next.insert(adjusted, moved);
      return s.copyWith(homeWidgetOrder: next);
    });
  }

  /// Decrypt the stacks envelope using [dek] and populate the in-memory
  /// stacks list. Returns true on success. Returns false if the envelope is
  /// missing (programming error — caller should check [stacksEncryptedAtRest]
  /// first) or fails the MAC check (corrupt blob).
  Future<bool> unlockWithDek(List<int> dek) async {
    if (!_repo.hasEncryptedStacks) return false;
    final stacks = await _repo.decryptStacks(dek);
    if (stacks == null) return false;
    _dek = dek;
    _state = _state.copyWith(stacks: stacks);
    notifyListeners();
    return true;
  }

  /// Drop the in-memory DEK and clear the stacks list. The on-disk envelope
  /// is left untouched. Idempotent.
  void relock() {
    if (_dek == null && _state.stacks.isEmpty) return;
    _dek = null;
    _state = _state.copyWith(stacks: const []);
    notifyListeners();
  }

  /// Adopt a DEK and immediately persist the current state under it. Used by
  /// the migration path after [StacksCryptoService.initWithPin] returns.
  Future<void> adoptDek(List<int> dek) async {
    _dek = dek;
    await _repo.save(_state, dek: dek);
  }

  /// Drop the cached envelope (decrypt-back path) and persist the current
  /// state as plaintext. Used when the user disables the lock entirely.
  Future<void> clearEncryptionAndSave() async {
    _dek = null;
    _repo.clearEncryptedStacks();
    await _repo.save(_state);
  }

  void _update(AppState Function(AppState) mutate) {
    final next = mutate(_state);
    if (identical(next, _state)) return;
    _state = next;
    notifyListeners();
    unawaited(_repo.save(next, dek: _dek));
  }
}
