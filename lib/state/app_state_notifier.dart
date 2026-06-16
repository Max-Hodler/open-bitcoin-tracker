import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../data/data.dart';

class AppStateNotifier extends ChangeNotifier with WidgetsBindingObserver {
  AppStateNotifier(this._repo) : _state = _repo.load() {
    // Observes lifecycle solely to flush a pending debounced save when the
    // app leaves the foreground.
    WidgetsBinding.instance.addObserver(this);
  }

  final AppStateRepository _repo;
  AppState _state;

  /// Quiet window for coalescing non-stack saves (converter keystrokes,
  /// settings churn). 500 ms turns a typing burst into at most two writes per
  /// second instead of one per keystroke, while bounding what a crash can
  /// lose to half a second of input. The timer is armed by the FIRST unsaved
  /// mutation and deliberately NOT reset by later ones, so continuous typing
  /// cannot postpone durability beyond this window.
  static const Duration saveDebounceWindow = Duration(milliseconds: 500);
  Timer? _saveTimer;
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

  // Debug-only screenshot mode. When on, `stacks` hands out a fixed demo set
  // (see [_screenshotStacks]) instead of the user's real stacks, so marketing
  // screenshots always show the same curated portfolio. The real `_state` is
  // never mutated, so toggling off restores the user's data untouched. Set in
  // lockstep with [LivePriceController.screenshotMode] from the Settings
  // toggle, which is itself gated to debug builds.
  bool _screenshotMode = false;
  bool get screenshotMode => _screenshotMode;
  set screenshotMode(bool value) {
    if (_screenshotMode == value) return;
    _screenshotMode = value;
    notifyListeners();
  }

  // The curated demo portfolio shown in screenshot mode. Snapshotted from the
  // author's own stacks; no avatar images or colour keys, so they render with
  // the default initial-letter avatars.
  static const List<Stack> _screenshotStacks = [
    Stack(id: 'shot-1', name: 'My Stack', sats: 68949327),
    Stack(id: 'shot-2', name: "Kids' Stack", sats: 35478965),
    Stack(id: 'shot-3', name: "Parents' Stack", sats: 9545236),
    Stack(id: 'shot-4', name: "Grandparents' Stack", sats: 4878655),
  ];

  List<Stack> get stacks => _screenshotMode ? _screenshotStacks : _state.stacks;
  // Stack count at the time of the last encrypt/relock, read from the repo so
  // it survives cold starts where stacks are never decrypted into memory.
  int get lockedStackCount => _repo.lockedStackCount;
  Currency get currency => _state.currency;
  List<Currency> get selectedCurrencies => _state.selectedCurrencies;
  bool get showPortfolio => _state.showPortfolio;
  bool get swipeChipHintDismissed => _state.swipeChipHintDismissed;
  bool get showChart => _state.showChart;
  bool get showPriceDelta => _state.showPriceDelta;
  ChartHeight get chartHeight => _state.chartHeight;
  AppTheme get theme => _state.theme;
  DarkVariant get darkVariant => _state.darkVariant;
  LightVariant get lightVariant => _state.lightVariant;
  BtcRange get btcRange => _state.btcRange;
  BtcRange get daysOverflowQuickRange => _state.daysOverflowQuickRange;
  BtcRange get weeksOverflowQuickRange => _state.weeksOverflowQuickRange;
  BtcRange get overflowQuickRange => _state.overflowQuickRange;
  BtcRange get monthsOverflowQuickRange => _state.monthsOverflowQuickRange;
  bool get logScale => _state.logScale;
  BtcDisplayMode get btcDisplayMode => _state.btcDisplayMode;
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

  /// Step the active currency through [selectedCurrencies] by [direction] (+1
  /// next, -1 previous), wrapping around. Returns true if the active currency
  /// changed, false if no swap was possible (0 or 1 currency in the ring — the
  /// caller is expected to handle that case, typically by opening the picker).
  bool cycleCurrency(int direction) {
    final ring = _state.selectedCurrencies;
    if (ring.length <= 1) return false;
    final i = ring.indexOf(_state.currency);
    // If the active currency was removed from the ring (e.g. cleared by an
    // external mutation), snap to the first ring entry rather than wrap
    // around index -1.
    final base = i < 0 ? 0 : i;
    final next = ring[(base + direction) % ring.length];
    if (next == _state.currency) return false;
    setCurrency(next);
    return true;
  }

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
  /// so values survive app restarts. Called on every keystroke; the
  /// [saveDebounceWindow] in [_update] coalesces a typing burst into a single
  /// write.
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
  /// home-screen swipe gesture cycles through. The list is deduplicated; if the
  /// currently displayed currency isn't in [next], the active currency snaps to
  /// the first entry.
  void setSelectedCurrencies(List<Currency> next) {
    final unique = <Currency>[];
    for (final c in next) {
      if (!unique.contains(c)) unique.add(c);
    }
    if (unique.isEmpty) return;
    final shouldSnap = !unique.contains(_state.currency);
    _update((s) => s.copyWith(
          selectedCurrencies: unique,
          currency: shouldSnap ? unique.first : s.currency,
        ));
  }
  void setShowPortfolio(bool value) => _update((s) => s.copyWith(showPortfolio: value));
  void dismissSwipeChipHint() =>
      _update((s) => s.copyWith(swipeChipHintDismissed: true));
  void setShowChart(bool value) => _update((s) => s.copyWith(showChart: value));
  void setShowPriceDelta(bool value) => _update((s) => s.copyWith(showPriceDelta: value));
  void setChartHeight(ChartHeight value) => _update((s) => s.copyWith(chartHeight: value));
  void setTheme(AppTheme value) => _update((s) => s.copyWith(theme: value));
  void setDarkVariant(DarkVariant value) =>
      _update((s) => s.copyWith(darkVariant: value));
  void setLightVariant(LightVariant value) =>
      _update((s) => s.copyWith(lightVariant: value));
  void setBtcRange(BtcRange value) => _update((s) => s.copyWith(btcRange: value));
  void setDaysOverflowQuickRange(BtcRange value) =>
      _update((s) => s.copyWith(daysOverflowQuickRange: value));
  void setWeeksOverflowQuickRange(BtcRange value) =>
      _update((s) => s.copyWith(weeksOverflowQuickRange: value));
  void setOverflowQuickRange(BtcRange value) =>
      _update((s) => s.copyWith(overflowQuickRange: value));
  void setMonthsOverflowQuickRange(BtcRange value) =>
      _update((s) => s.copyWith(monthsOverflowQuickRange: value));
  void setLogScale(bool value) => _update((s) => s.copyWith(logScale: value));
  void setBitcoinDisplayMode(BtcDisplayMode value) =>
      _update((s) => s.copyWith(btcDisplayMode: value));
  void setStacksAuthMode(StacksAuthMode value) =>
      _update((s) => s.copyWith(stacksAuthMode: value));
  void setStacksLockTimeout(StacksLockTimeout value) =>
      _update((s) => s.copyWith(stacksLockTimeout: value));
  void setLanguage(LanguagePref value) =>
      _update((s) => s.copyWith(language: value));
  void setLivePriceCadence(LivePriceCadence value) =>
      _update((s) => s.copyWith(livePriceCadence: value));

  // Total card avatar customization. Pass null to revert to the default
  // (initial-letter circle in the theme's bitcoinOrange).
  void setTotalImageData(String? value) => _update((s) => value == null
      ? s.copyWith(clearTotalImage: true)
      : s.copyWith(totalImageData: value));
  void setTotalColorKey(String? value) => _update((s) => value == null
      ? s.copyWith(clearTotalColor: true)
      : s.copyWith(totalColorKey: value));
  void setTotalProjectedPrice(double? price, String currencyCode) =>
      _update((s) => price == null
          ? s.copyWith(clearTotalProjectedPrice: true)
          : s.copyWith(
              totalProjectedPrice: price,
              totalProjectedPriceCurrency: currencyCode,
            ));

  void addStack(Stack stack) => _update((s) => s.copyWith(
        stacks: [stack, ...s.stacks],
      ));

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
    _cancelPendingSave(); // this save carries the full latest state
    await _repo.save(_state, dek: dek);
  }

  /// Drop the cached envelope (decrypt-back path) and persist the current
  /// state as plaintext. Used when the user disables the lock entirely.
  Future<void> clearEncryptionAndSave() async {
    _dek = null;
    _repo.clearEncryptedStacks();
    _cancelPendingSave(); // this save carries the full latest state
    await _repo.save(_state);
  }

  void _update(AppState Function(AppState) mutate) {
    final next = mutate(_state);
    if (identical(next, _state)) return;
    // Stack mutations stay durable immediately; everything else (settings,
    // converter entries) is coalesced through the debounce window. copyWith
    // keeps the stacks list object when it isn't part of the change, so an
    // identity flip is exactly "this mutation touched the stacks".
    final stacksChanged = !identical(next.stacks, _state.stacks);
    _state = next;
    notifyListeners();
    if (stacksChanged) {
      _saveNow();
    } else {
      _saveTimer ??= Timer(saveDebounceWindow, _saveNow);
    }
  }

  void _saveNow() {
    _cancelPendingSave();
    unawaited(_repo.save(_state, dek: _dek));
  }

  void _cancelPendingSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  /// Persist immediately if a debounced save is pending. Called from the
  /// lifecycle hook below so a backgrounded app never sits on unsaved input.
  void flushPendingSave() {
    if (_saveTimer == null) return;
    _saveNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        flushPendingSave();
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void dispose() {
    flushPendingSave();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
