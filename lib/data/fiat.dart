import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../data/app_enums.dart';
import '../data/sats.dart';
import '../l10n/generated/app_localizations.dart';

String currencyLabel(AppLocalizations l10n, Currency c) => switch (c) {
      Currency.usd => l10n.currencyLabelUsd,
      Currency.eur => l10n.currencyLabelEur,
      Currency.gbp => l10n.currencyLabelGbp,
      Currency.aud => l10n.currencyLabelAud,
      Currency.cad => l10n.currencyLabelCad,
      Currency.chf => l10n.currencyLabelChf,
      Currency.jpy => l10n.currencyLabelJpy,
    };

const Map<Currency, String> currencySymbols = {
  Currency.usd: r'$',
  Currency.gbp: '£',
  Currency.eur: '€',
  Currency.jpy: '¥',
  Currency.cad: r'CA$',
  Currency.aud: r'A$',
  Currency.chf: 'CHF ',
};

/// True when the active locale places the currency symbol after the number
/// (e.g. Spanish: "78.276 $") rather than before (e.g. English: "$78,276").
/// Asks NumberFormat.currency directly so intl owns the placement rule.
bool get symbolAfterAmount {
  const sentinel = '¤'; // generic currency sign used as a probe
  final sample = NumberFormat.currency(
    locale: Intl.defaultLocale,
    symbol: sentinel,
    decimalDigits: 0,
  ).format(1);
  return !sample.startsWith(sentinel);
}

class FiatFormat {
  const FiatFormat({required this.symbol, required this.amount});

  final String symbol;
  final String amount;

  String get full =>
      symbolAfterAmount ? '$amount $symbol' : '$symbol $amount';

  /// Like [full] but with no gap between the symbol and the amount.
  String get tight =>
      symbolAfterAmount ? '$amount$symbol' : '$symbol$amount';
}

/// The decimal separator character for the active locale (e.g. ',' in Spanish, '.' in English).
String get localeDecimalSeparator {
  final sample = NumberFormat.decimalPattern(Intl.defaultLocale).format(1.1);
  return sample.contains(',') ? ',' : '.';
}

// Kept for callers (e.g. sats counts) that want grouped digits in whatever
// locale is currently active. `Intl.defaultLocale` is synced from
// AppStateNotifier.language at app boot, so this picks up the user's choice.
NumberFormat get intFormatter =>
    NumberFormat.decimalPattern(Intl.defaultLocale);

FiatFormat formatFiat(double value, Currency currency, {bool decimalsUnder10 = false}) {
  final symbol = currencySymbols[currency] ?? r'$';
  final locale = Intl.defaultLocale;
  final whole = NumberFormat.decimalPattern(locale);
  if (!decimalsUnder10) {
    return FiatFormat(symbol: symbol, amount: whole.format(value.round()));
  }
  final abs = value.abs();
  final String amount;
  if (abs >= 10) {
    amount = whole.format(value.round());
  } else if (abs >= 1 || abs == 0) {
    amount = NumberFormat('#,##0.0', locale).format(value);
  } else {
    amount = _formatSmallFiat(value);
  }
  return FiatFormat(symbol: symbol, amount: amount);
}

String _formatSmallFiat(double value) {
  final abs = value.abs();
  // Pick enough decimals so the first non-zero digit is shown (plus one more
  // significant digit for precision), capped to avoid runaway length.
  final magnitude = -(math.log(abs) / math.ln10).floor();
  final decimals = math.min(10, math.max(2, magnitude + 1));
  var s = value.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// Caps the fractional digits we render or accept in fiat input so that
/// converter-style round-trips (sats → fiat → sats) are lossless against the
/// displayed value.
const int kFiatMaxDecimals = 10;

/// Formats a canonical fiat raw string (digits with '.' decimal separator and
/// no grouping) for display in the active locale: thousands grouping applied,
/// decimal point swapped for the locale's separator. Used by the converter
/// (active side input) and any other screen that displays a derived fiat
/// amount via [formatDerivedFiatValue].
String formatFiatRaw(String raw) {
  if (raw.isEmpty) return '';
  final sep = localeDecimalSeparator;
  if (!raw.contains('.')) {
    return groupDigits(raw);
  }
  final parts = raw.split('.');
  final head = groupDigits(parts[0].isEmpty ? '0' : parts[0]);
  return '$head$sep${parts.length > 1 ? parts[1] : ''}';
}

/// Applies the active locale's thousands grouping to a digit string of any
/// length. Falls back to manual grouping past `int` range so very long inputs
/// (e.g. typing 20+ digits in the converter) still get punctuation instead of
/// silently rendering as one unbroken run of digits.
String groupDigits(String digits) {
  if (digits.isEmpty) return digits;
  final n = int.tryParse(digits);
  if (n != null) return intFormatter.format(n);
  final groupSep = intFormatter.symbols.GROUP_SEP;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) buf.write(groupSep);
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Returns a derived fiat value as a canonical raw string ('.'-separated, no
/// grouping). For |value| >= 1 we clamp to exactly 2 fractional digits so
/// large amounts don't display sub-cent noise; below 1 we keep full
/// [kFiatMaxDecimals] precision (trailing zeros trimmed) so dust amounts stay
/// meaningful. Returns '' for zero.
String clampDerivedFiatRaw(double value) {
  if (value == 0) return '';
  if (value.abs() >= 1) return value.toStringAsFixed(2);
  final s = value.toStringAsFixed(kFiatMaxDecimals);
  return s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s;
}

/// Renders a derived fiat double for display in the active locale, applying
/// the [clampDerivedFiatRaw] precision rule.
String formatDerivedFiatValue(double value) {
  if (value == 0) return '0';
  return formatFiatRaw(clampDerivedFiatRaw(value));
}

String formatBtcAmount(
  int sats, {
  bool hidden = false,
  BtcDisplayMode mode = BtcDisplayMode.sats,
}) {
  if (hidden) return '**** **** ****';
  final amount = switch (mode) {
    BtcDisplayMode.sats =>
      NumberFormat.decimalPattern(Intl.defaultLocale).format(sats),
    BtcDisplayMode.btc => _formatBtcFromSats(sats),
  };
  return symbolAfterAmount ? '$amount ₿' : '₿ $amount';
}

/// Renders [sats] as a BTC amount in the active locale: thousands grouping on
/// the integer part, locale decimal separator, and up to 8 fractional digits
/// with trailing zeros trimmed. Zero renders as `0` (no decimal part).
String _formatBtcFromSats(int sats) {
  if (sats == 0) return '0';
  final whole = sats ~/ Sats.perBtc;
  final fraction = sats.remainder(Sats.perBtc).abs();
  final wholeStr =
      NumberFormat.decimalPattern(Intl.defaultLocale).format(whole);
  if (fraction == 0) return wholeStr;
  var fracStr = fraction.toString().padLeft(8, '0');
  fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
  // Negative sub-BTC amounts (e.g. -50000 sats) lose their sign when split via
  // integer truncation — `whole` is 0, so prefix the minus manually.
  final sign = sats < 0 && whole == 0 ? '-' : '';
  return '$sign$wholeStr$localeDecimalSeparator$fracStr';
}
