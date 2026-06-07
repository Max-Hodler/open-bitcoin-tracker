import '../../api/api.dart';
import '../../data/app_enums.dart';

/// Slices the full all-history series to the window for [range], with a small
/// one-entry cache so repeated calls with the same `(all, range)` don't redo
/// the binary search on every chart rebuild.
///
/// Lives outside the home screen state so it can be unit-tested directly. The
/// cache key uses `identical()` reference equality — fine because the
/// controller hands the home screen the same list object until a new fetch
/// rebuilds it.
class ChartSlicer {
  List<HistoryPoint>? _source;
  BtcRange? _range;
  List<HistoryPoint> _cached = const [];

  List<HistoryPoint> slice(List<HistoryPoint> all, BtcRange range) {
    if (identical(all, _source) && range == _range) return _cached;
    _source = all;
    _range = range;
    if (range == BtcRange.all || all.isEmpty) {
      _cached = all;
      return _cached;
    }
    final cutoff = all.last.timeMs - _daysFor(range) * 86400000;
    var lo = 0, hi = all.length - 1, start = all.length;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (all[mid].timeMs >= cutoff) {
        start = mid;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    _cached = start == 0 ? all : all.sublist(start);
    return _cached;
  }
}

int _daysFor(BtcRange range) => switch (range) {
      BtcRange.m2 => 60,
      BtcRange.m3 => 90,
      BtcRange.m4 => 120,
      BtcRange.m5 => 150,
      BtcRange.m6 => 180,
      BtcRange.m7 => 210,
      BtcRange.m8 => 240,
      BtcRange.m9 => 270,
      BtcRange.m10 => 300,
      BtcRange.m11 => 330,
      BtcRange.m12 => 365,
      BtcRange.y1 => 365,
      BtcRange.y2 => 730,
      BtcRange.y3 => 1095,
      BtcRange.y4 => 1460,
      BtcRange.y5 => 1825,
      BtcRange.y6 => 2190,
      BtcRange.y7 => 2555,
      BtcRange.y8 => 2920,
      BtcRange.y9 => 3285,
      BtcRange.y10 => 3650,
      BtcRange.y11 => 4015,
      BtcRange.y12 => 4380,
      BtcRange.y13 => 4745,
      BtcRange.y14 => 5110,
      BtcRange.y15 => 5475,
      _ => 3650,
    };
