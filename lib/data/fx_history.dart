import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_enums.dart';

/// Bundled daily USD->fiat exchange-rate history (ECB reference rates).
///
/// Mirrors [loadBundledHistory] / `btc_history.dart`: the USD-only BTC series
/// is converted per-day by looking up that day's FX rate, so a long-range
/// non-USD chart reflects historic currency moves instead of being a flat
/// rescale by today's rate.
///
/// Source CSV is `assets/fx_history.csv`, one row per date with columns
/// `date,EUR,GBP,AUD,CAD,CHF,JPY` (no USD column — it is always 1.0).
class FxHistory {
  FxHistory._(this._days, this._rates);

  // currency -> parallel arrays, sorted ascending by time.
  final Map<Currency, List<int>> _days; // timeMs
  final Map<Currency, List<double>> _rates; // usd->currency

  /// USD->[c] rate effective on or before [timeMs] (binary search).
  ///
  /// [Currency.usd] is always 1.0. Out-of-range times clamp to the first /
  /// last known entry. Returns 1.0 if the currency has no data at all.
  double rateAt(Currency c, int timeMs) {
    if (c == Currency.usd) return 1.0;
    final days = _days[c];
    final rates = _rates[c];
    if (days == null || rates == null || days.isEmpty) return 1.0;

    if (timeMs <= days.first) return rates.first;
    if (timeMs >= days.last) return rates.last;

    // Largest index with days[index] <= timeMs.
    var lo = 0;
    var hi = days.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (days[mid] <= timeMs) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return rates[lo];
  }
}

Future<FxHistory> loadBundledFxHistory() async {
  final raw = await rootBundle.loadString('assets/fx_history.csv');
  return compute(_parseFxCsv, raw);
}

// Column order in assets/fx_history.csv after the `date` column. Fixed.
const List<Currency> _fxColumns = [
  Currency.eur,
  Currency.gbp,
  Currency.aud,
  Currency.cad,
  Currency.chf,
  Currency.jpy,
];

FxHistory _parseFxCsv(String raw) {
  final days = {for (final c in _fxColumns) c: <int>[]};
  final rates = {for (final c in _fxColumns) c: <double>[]};

  final lines = raw.split('\n');
  for (final line in lines) {
    final parts = line.trim().split(',');
    if (parts.length < _fxColumns.length + 1) continue;
    final date = DateTime.tryParse(parts[0]);
    if (date == null) continue; // skips the header row
    final timeMs = date.millisecondsSinceEpoch;
    for (var i = 0; i < _fxColumns.length; i++) {
      final rate = double.tryParse(parts[i + 1]);
      if (rate == null || rate <= 0) continue;
      final c = _fxColumns[i];
      days[c]!.add(timeMs);
      rates[c]!.add(rate);
    }
  }
  return FxHistory._(days, rates);
}
