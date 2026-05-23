import '../data/app_enums.dart';
import '../data/sats.dart';
import '../format/fiat.dart';
import 'converter_state.dart';

/// What unit a slot's raw string is interpreted in.
///
/// One slot holds fiat (currency), the other holds a Bitcoin amount in either
/// sats (integer string) or BTC (decimal string). Routing all conversion
/// through sats keeps the BTC↔sats path pure and free of the live rate.
enum ConverterInputUnit { fiat, sats, btc }

/// Resolves the unit of a given (mode, slot) pair under the converter's
/// current Bitcoin display setting.
ConverterInputUnit slotUnit(
  ConverterMode mode,
  ConverterSlot slot,
  BtcDisplayMode btcMode,
) {
  switch (mode) {
    case ConverterMode.fiat:
      if (slot == ConverterSlot.top) return ConverterInputUnit.fiat;
      return btcMode == BtcDisplayMode.btc
          ? ConverterInputUnit.btc
          : ConverterInputUnit.sats;
    case ConverterMode.sats:
      if (slot == ConverterSlot.top) return ConverterInputUnit.sats;
      return ConverterInputUnit.btc;
  }
}

/// Whether the active slot accepts a decimal separator. Sats are integers, so
/// the keypad hides the decimal key for that unit.
bool activeAllowsDecimal(
  ConverterMode mode,
  ConverterSlot active,
  BtcDisplayMode btcMode,
) =>
    slotUnit(mode, active, btcMode) != ConverterInputUnit.sats;

/// Whether a leading '0' keystroke should be suppressed: sats input doesn't
/// admit leading zeros, so an empty sats slot rejects the first '0'.
bool leadingZeroBlocked(
  ConverterMode mode,
  ConverterSlot active,
  String raw,
  BtcDisplayMode btcMode,
) =>
    raw.isEmpty && slotUnit(mode, active, btcMode) == ConverterInputUnit.sats;

/// Both slots' raw strings for this build. The active slot is the user's
/// in-progress input verbatim; the other is derived via the live BTC price
/// (fiat mode) or a pure sats↔BTC conversion (sats mode). The derived string
/// may be empty when the rate isn't available yet or the input rounds to zero.
({String top, String bottom}) deriveRaws({
  required ConverterMode mode,
  required ConverterSlot active,
  required String raw,
  required BtcDisplayMode btcMode,
  required double rate,
}) {
  final fromUnit = slotUnit(mode, active, btcMode);
  final otherSlot =
      active == ConverterSlot.top ? ConverterSlot.bottom : ConverterSlot.top;
  final toUnit = slotUnit(mode, otherSlot, btcMode);
  final derived = convertRaw(raw, from: fromUnit, to: toUnit, rate: rate);
  return active == ConverterSlot.top
      ? (top: raw, bottom: derived)
      : (top: derived, bottom: raw);
}

/// Converts a raw string between two units, routing through sats. The rate is
/// only needed when fiat is involved on either side; pure BTC↔sats works even
/// before the BTC price has loaded.
String convertRaw(
  String raw, {
  required ConverterInputUnit from,
  required ConverterInputUnit to,
  required double rate,
}) {
  if (from == to) return raw;
  if (raw.isEmpty) return '';
  final fiatInvolved =
      from == ConverterInputUnit.fiat || to == ConverterInputUnit.fiat;
  if (fiatInvolved && rate <= 0) return '';
  return satsToRaw(rawToSats(raw, from, rate), to, rate);
}

/// Parses a raw input string into sats. Returns 0 if parsing fails or the
/// value is zero. For fiat→sats, uses the live rate.
int rawToSats(String raw, ConverterInputUnit unit, double rate) {
  if (raw.isEmpty) return 0;
  switch (unit) {
    case ConverterInputUnit.fiat:
      if (rate <= 0) return 0;
      final fiat = double.tryParse(raw) ?? 0;
      return fiat == 0 ? 0 : (fiat / rate * Sats.perBtc).round();
    case ConverterInputUnit.sats:
      return int.tryParse(raw) ?? 0;
    case ConverterInputUnit.btc:
      return Sats.btcRawToSats(raw);
  }
}

/// Renders an int sats value as a raw input string in the target unit.
/// Returns '' for zero so the inactive slot reads as empty rather than '0'.
String satsToRaw(int sats, ConverterInputUnit unit, double rate) {
  if (sats == 0) return '';
  switch (unit) {
    case ConverterInputUnit.fiat:
      if (rate <= 0) return '';
      return clampDerivedFiatRaw(sats / Sats.perBtc * rate);
    case ConverterInputUnit.sats:
      return sats.toString();
    case ConverterInputUnit.btc:
      return Sats.satsToBtcRaw(sats);
  }
}

/// Returns the new raw input + caret position after inserting [v] at [caret]
/// into a string in the given [unit], or null if the keystroke should be
/// rejected (caller suppresses haptic/visual change).
(String, int)? insertChar(
  String raw,
  int caret,
  String v,
  ConverterInputUnit unit,
) {
  if (unit == ConverterInputUnit.sats) {
    if (v == '.') return null;
    if (raw.length >= Sats.maxInputDigits) return null;
    if (v == '0' && caret == 0 && raw.isNotEmpty) return null;
    return ('${raw.substring(0, caret)}$v${raw.substring(caret)}', caret + 1);
  }
  // Fiat or BTC display: digits + at most one '.', capped at the unit's max
  // fractional digits (8 for BTC, kFiatMaxDecimals for fiat).
  final maxDecimals = unit == ConverterInputUnit.btc ? 8 : kFiatMaxDecimals;
  if (v == '.') {
    if (raw.contains('.')) return null;
    if (raw.isEmpty) return ('0.', 2);
    return ('${raw.substring(0, caret)}.${raw.substring(caret)}', caret + 1);
  }
  if (raw.contains('.')) {
    final dot = raw.indexOf('.');
    final fracLen = raw.length - dot - 1;
    if (caret > dot && fracLen >= maxDecimals) return null;
  }
  return ('${raw.substring(0, caret)}$v${raw.substring(caret)}', caret + 1);
}

/// Builds a [ConverterEntry] from persisted strings, defaulting an unknown or
/// null slot code to [ConverterSlot.top] and placing the caret at the end of
/// the input.
ConverterEntry entryFrom(String? raw, String? slotCode) {
  final r = raw ?? '';
  return ConverterEntry(
    raw: r,
    active: parseSlot(slotCode) ?? ConverterSlot.top,
    caret: r.length,
  );
}

ConverterSlot? parseSlot(String? code) {
  for (final s in ConverterSlot.values) {
    if (s.name == code) return s;
  }
  return null;
}

ConverterMode? parseMode(String? code) {
  for (final m in ConverterMode.values) {
    if (m.name == code) return m;
  }
  return null;
}
