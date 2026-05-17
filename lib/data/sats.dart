class Sats {
  Sats._();

  static const int perBtc = 100000000;
  static const int maxSupply = 21000000 * perBtc;
  static const int maxInputDigits = 17;

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
}
