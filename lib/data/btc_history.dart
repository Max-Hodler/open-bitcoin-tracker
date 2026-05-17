import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/price_data.dart';

Future<List<HistoryPoint>> loadBundledHistory() async {
  final raw = await rootBundle.loadString('assets/btc_history.csv');
  return compute(_parseHistoryCsv, raw);
}

List<HistoryPoint> _parseHistoryCsv(String raw) {
  final lines = raw.split('\n');
  final out = <HistoryPoint>[];
  for (final line in lines) {
    final parts = line.trim().split(',');
    if (parts.length < 2) continue;
    final date = DateTime.tryParse(parts[0]);
    final price = double.tryParse(parts[1]);
    if (date == null || price == null || price <= 0) continue;
    out.add(HistoryPoint(date.millisecondsSinceEpoch, price));
  }
  return out;
}
