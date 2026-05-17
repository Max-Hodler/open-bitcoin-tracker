import 'package:flutter/foundation.dart';

import '../data/app_enums.dart';
import '../data/sats.dart';

/// Which two units the converter is currently bridging.
/// - [fiat]: fiat ↔ Bitcoin (uses live BTC rate)
/// - [sats]: BTC ↔ sats (pure unit conversion, no rate)
enum ConverterMode { fiat, sats }

/// The two cards on the converter screen, by visual position. The previous
/// `ConverterSide.fiat`/`sats` naming had different meanings in each mode
/// (the "fiat" slot held sats in sats mode); `top`/`bottom` is mode-neutral.
enum ConverterSlot { top, bottom }

/// Per-mode state: what the user is typing, where the caret sits, and which
/// slot they're typing into. The non-active slot is always derived at render
/// time; it never lives in state.
@immutable
class ConverterEntry {
  const ConverterEntry({
    this.raw = '',
    this.caret = 0,
    this.active = ConverterSlot.top,
  });

  /// The raw string the user has typed, in the active slot's display unit.
  /// Locale-neutral: '.' decimal separator, no grouping. Empty == no input.
  final String raw;
  // Caret position in [raw], in [0, raw.length].
  final int caret;
  // Which slot the user is editing.
  final ConverterSlot active;

  ConverterEntry copyWith({String? raw, int? caret, ConverterSlot? active}) =>
      ConverterEntry(
        raw: raw ?? this.raw,
        caret: caret ?? this.caret,
        active: active ?? this.active,
      );
}

/// Single source of truth for the converter screen.
///
/// Two independent [ConverterEntry] snapshots, one per [ConverterMode], swap
/// in and out as the user toggles modes — so in-progress input in one mode
/// survives a trip through the other.
///
/// The fiat-mode bottom slot's raw is stored in whichever Bitcoin display
/// unit (sats integer vs BTC decimal) the converter was set to at the time
/// the user typed it. Display-unit changes go through [migrateFiatBtcDisplay]
/// from the picker handler — a synchronous, one-shot conversion — so the
/// unit interpretation of [raw] is always coherent with the *current* state,
/// without any post-frame re-sync machinery or "last-seen mode" bookkeeping.
class ConverterState extends ChangeNotifier {
  ConverterMode mode = ConverterMode.fiat;
  ConverterEntry _fiat = const ConverterEntry();
  ConverterEntry _sats = const ConverterEntry();
  bool showLeadingZeroWarning = false;
  // Optional persistence hooks installed by the screen. [onPersist] fires
  // on every entry mutation (per-mode keystrokes, slot flips); [onPersistMode]
  // fires whenever the user toggles the converter mode. The screen routes
  // both into AppStateNotifier so values + mode survive app restarts.
  void Function(ConverterMode mode, ConverterEntry entry)? onPersist;
  void Function(ConverterMode mode)? onPersistMode;

  ConverterEntry get _live => mode == ConverterMode.fiat ? _fiat : _sats;

  String get raw => _live.raw;
  int get caret => _live.caret;
  ConverterSlot get active => _live.active;

  bool _hydrated = false;

  /// First call wins; subsequent calls are no-ops so it's safe to call from
  /// the screen's build method. Bypasses [onPersist]/[onPersistMode] — the
  /// caller is the source of truth.
  void hydrateOnce({
    required ConverterEntry fiat,
    required ConverterEntry sats,
    required ConverterMode mode,
  }) {
    if (_hydrated) return;
    _hydrated = true;
    _fiat = fiat;
    _sats = sats;
    this.mode = mode;
  }

  void _write(ConverterEntry next) {
    if (mode == ConverterMode.fiat) {
      _fiat = next;
    } else {
      _sats = next;
    }
    onPersist?.call(mode, next);
  }

  /// Replaces fields on the live entry. Notifies only if something changed.
  void edit({String? raw, int? caret, ConverterSlot? active, bool? warning}) {
    final cur = _live;
    final nextRaw = raw ?? cur.raw;
    final nextActive = active ?? cur.active;
    final nextCaret = raw != null
        ? (caret ?? nextRaw.length)
        : (caret != null ? caret.clamp(0, nextRaw.length) : cur.caret);
    final entryChanged = nextRaw != cur.raw ||
        nextActive != cur.active ||
        nextCaret != cur.caret;
    final warningChanged = warning != null && warning != showLeadingZeroWarning;
    if (entryChanged) {
      _write(ConverterEntry(raw: nextRaw, caret: nextCaret, active: nextActive));
    }
    if (warningChanged) showLeadingZeroWarning = warning;
    if (entryChanged || warningChanged) notifyListeners();
  }

  /// Toggles the converter mode. Preserves the other mode's snapshot so the
  /// user can flip back and find their work intact.
  void setMode(ConverterMode next) {
    if (mode == next) return;
    mode = next;
    showLeadingZeroWarning = false;
    onPersistMode?.call(next);
    notifyListeners();
  }

  /// Reinterprets the fiat-mode bottom-slot raw (sats ↔ BTC) when the user
  /// changes the converter's Bitcoin display unit via the picker. Called
  /// synchronously from the picker handler **before** the global setting
  /// flips, so the screen rebuild sees a coherent (raw, display-unit) pair
  /// in one step. No effect in sats mode (the bottom slot there is always
  /// BTC regardless of the display setting).
  void migrateFiatBtcDisplay(BtcDisplayMode from, BtcDisplayMode to) {
    if (from == to) return;
    if (_fiat.active != ConverterSlot.bottom || _fiat.raw.isEmpty) return;
    final String nextRaw;
    if (to == BtcDisplayMode.btc) {
      // sats integer string → BTC decimal string
      nextRaw = Sats.satsToBtcRaw(int.tryParse(_fiat.raw) ?? 0);
    } else {
      // BTC decimal string → sats integer string
      final sats = Sats.btcRawToSats(_fiat.raw);
      nextRaw = sats == 0 ? '' : sats.toString();
    }
    final wasFiatMode = mode == ConverterMode.fiat;
    _fiat = _fiat.copyWith(raw: nextRaw, caret: nextRaw.length);
    onPersist?.call(ConverterMode.fiat, _fiat);
    if (wasFiatMode) notifyListeners();
  }
}
