class Sats {
  Sats._();

  static const int perBtc = 100000000;
  static const int maxSupply = 21000000 * perBtc;
  static const int maxInputDigits = 17;

  // Max fractional digits in a BTC raw input string. Matches the 8 decimals of
  // canonical satoshis, so the rounded sats value is lossless.
  static const int btcMaxDecimals = 8;

  static double toBtc(int sats) => sats / perBtc;
  static int fromBtc(double btc) => (btc * perBtc).round();

  static double toFiat(int sats, double btcFiatRate) => toBtc(sats) * btcFiatRate;

  /// Renders [sats] as a BTC raw string: integer + '.' + ≤8 fractional
  /// digits with trailing zeros trimmed. `0` returns `''` (empty raw input
  /// convention), whole-BTC values return just the integer part
  /// (e.g. `100000000` → `'1'`).
  static String satsToBtcRaw(int sats) {
    if (sats == 0) return '';
    final whole = sats ~/ perBtc;
    final fraction = sats.remainder(perBtc).abs();
    if (fraction == 0) return whole.toString();
    var fracStr = fraction.toString().padLeft(8, '0');
    fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$fracStr';
  }

  /// Parses a BTC raw string (`'1.5'`, `'0.001'`) into whole sats. Returns
  /// 0 for empty input or unparseable strings.
  static int btcRawToSats(String btcRaw) {
    if (btcRaw.isEmpty) return 0;
    final btc = double.tryParse(btcRaw) ?? 0;
    return fromBtc(btc);
  }

  /// Returns the new (input, caret) after inserting [ch] (a digit or `'.'`) at
  /// [caret] in a BTC-mode amount input. Returns null when the keystroke
  /// should be ignored: a second decimal point, exceeding the 8-decimal
  /// fractional cap, leading zero on a non-zero integer part, or going past
  /// the 21M supply.
  static (String, int)? tryInsertBtcChar(String input, int caret, String ch) {
    if (ch == '.') {
      if (input.contains('.')) return null;
      if (input.isEmpty) {
        // First char: render as '0.' with caret after the dot.
        return ('0.', 2);
      }
      return ('${input.substring(0, caret)}.${input.substring(caret)}', caret + 1);
    }
    if (input.contains('.')) {
      final dot = input.indexOf('.');
      final fracLen = input.length - dot - 1;
      final insertingInFraction = caret > dot;
      if (insertingInFraction && fracLen >= btcMaxDecimals) return null;
    }
    final next = '${input.substring(0, caret)}$ch${input.substring(caret)}';
    // Strip the leading-zero rule from sats mode: "0.001" is valid, but reject
    // pure leading-zero integer parts like "07" (jump to "7" instead would
    // surprise the user mid-edit, so just block the insert).
    if (ch == '0' &&
        caret == 0 &&
        input.isNotEmpty &&
        !input.startsWith('0')) {
      return null;
    }
    if (!_btcInputWithinSupply(next)) return null;
    return (next, caret + 1);
  }

  static bool _btcInputWithinSupply(String input) {
    final parsed = double.tryParse(input);
    if (parsed == null) return false;
    // Generous epsilon to allow typing the exact cap (21000000) without
    // floating-point error rejecting it.
    return parsed <= 21000000.000000005;
  }

  /// Strips everything but ASCII digits, trims leading zeros, and validates the
  /// result fits the sats-input constraints (digit cap + supply cap, non-zero).
  /// Returns null if the clipboard contents can't yield a valid amount.
  static String? sanitizePastedSats(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;
    final trimmed = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
    if (trimmed.isEmpty) return null;
    if (trimmed.length > maxInputDigits) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed == 0) return null;
    if (parsed > maxSupply) return null;
    return trimmed;
  }

  /// Sanitizes a clipboard string for the BTC-mode amount input. Accepts a
  /// decimal number using either '.' or ',' as the separator (so users can
  /// paste from locales other than the active one); the returned raw uses '.'
  /// to match the in-app canonical form. Caps fractional digits at 8 and
  /// validates against the 21M supply.
  static String? sanitizePastedBtc(String raw) {
    // Drop everything but digits and the two common decimal separators.
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (cleaned.isEmpty) return null;
    // Pick the *last* separator as the decimal point; treat any earlier
    // separators as grouping noise and strip them. Handles "1,234.56" (en)
    // and "1.234,56" (es) without needing to know the source locale.
    String normalized;
    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    final lastSep = lastDot > lastComma ? lastDot : lastComma;
    if (lastSep < 0) {
      normalized = cleaned;
    } else {
      final intPart =
          cleaned.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');
      final fracPart = cleaned.substring(lastSep + 1);
      if (fracPart.contains(RegExp(r'[.,]'))) return null;
      normalized = fracPart.isEmpty ? intPart : '$intPart.$fracPart';
    }
    if (normalized.isEmpty || normalized == '.') return null;
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed <= 0) return null;
    // Round-trip through sats so the value matches the keypad's max-supply
    // gate and we honor the 8-decimal cap. Re-derive raw from sats so trailing
    // zeros are trimmed and we never echo back more than 8 fractional digits.
    final sats = (parsed * perBtc).round();
    if (sats <= 0 || sats > maxSupply) return null;
    return satsToBtcRaw(sats);
  }
}
