import 'package:flutter_test/flutter_test.dart';
import 'package:open_bitcoin_tracker/data/app_enums.dart';

void main() {
  group('BtcRange', () {
    test('every value round-trips through fromCode', () {
      for (final r in BtcRange.values) {
        expect(BtcRange.fromCode(r.code), r, reason: 'failed on ${r.name}');
      }
    });

    test('the persisted code strings are stable', () {
      // SharedPreferences serializes BtcRange via .code, so these strings are
      // durable user data and must not change without a migration.
      expect(BtcRange.d1.code, '1D');
      expect(BtcRange.d7.code, '7D');
      expect(BtcRange.w1.code, '1W');
      expect(BtcRange.w4.code, '4W');
      expect(BtcRange.m1.code, '1M');
      expect(BtcRange.m12.code, '12M');
      expect(BtcRange.y1.code, '1Y');
      expect(BtcRange.y15.code, '15Y');
      expect(BtcRange.all.code, 'All');
    });

    test('fromCode falls back to y10 on unknown / null input', () {
      expect(BtcRange.fromCode(null), BtcRange.y10);
      expect(BtcRange.fromCode(''), BtcRange.y10);
      expect(BtcRange.fromCode('bogus'), BtcRange.y10);
    });

    test('days returns 1..7 for d1..d7 and null elsewhere', () {
      for (var i = 1; i <= 7; i++) {
        final r = BtcRange.values.firstWhere((r) => r.name == 'd$i');
        expect(r.days, i, reason: '${r.name} should report $i days');
        expect(r.isDays, isTrue);
        expect(r.isWeeks, isFalse);
        expect(r.isMonths, isFalse);
      }
      for (final r in [BtcRange.w1, BtcRange.m1, BtcRange.y1, BtcRange.all]) {
        expect(r.days, isNull, reason: '${r.name} is not day-shaped');
        expect(r.isDays, isFalse);
      }
    });

    test('weeks returns 1..4 for w1..w4 and null elsewhere', () {
      for (var i = 1; i <= 4; i++) {
        final r = BtcRange.values.firstWhere((r) => r.name == 'w$i');
        expect(r.weeks, i, reason: '${r.name} should report $i weeks');
        expect(r.isWeeks, isTrue);
        expect(r.isDays, isFalse);
      }
      for (final r in [BtcRange.d1, BtcRange.m1, BtcRange.y1, BtcRange.all]) {
        expect(r.weeks, isNull, reason: '${r.name} is not week-shaped');
        expect(r.isWeeks, isFalse);
      }
    });

    test('months returns 1..12 for m1..m12 and null elsewhere', () {
      for (var i = 1; i <= 12; i++) {
        final r = BtcRange.values.firstWhere((r) => r.name == 'm$i');
        expect(r.months, i, reason: '${r.name} should report $i months');
        expect(r.isMonths, isTrue);
        expect(r.isYears, isFalse);
      }
      for (final r in [BtcRange.d1, BtcRange.w1, BtcRange.y1,
          BtcRange.y15, BtcRange.all]) {
        expect(r.months, isNull, reason: '${r.name} is not month-shaped');
        expect(r.isMonths, isFalse);
      }
    });

    test('years returns 1..15 for y1..y15 and null elsewhere', () {
      for (var i = 1; i <= 15; i++) {
        final r = BtcRange.values.firstWhere((r) => r.name == 'y$i');
        expect(r.years, i, reason: '${r.name} should report $i years');
        expect(r.isYears, isTrue);
        expect(r.isMonths, isFalse);
      }
      for (final r in [BtcRange.d1, BtcRange.w1, BtcRange.m1, BtcRange.m12,
          BtcRange.all]) {
        expect(r.years, isNull, reason: '${r.name} is not year-shaped');
        expect(r.isYears, isFalse);
      }
    });

    test('isShortRange covers exactly d1..d7, w1..w4, and m1', () {
      for (final r in BtcRange.values) {
        expect(r.isShortRange, r.isDays || r.isWeeks || r == BtcRange.m1,
            reason: '${r.name} short-range mismatch');
      }
    });

    test('usesAllHistory is the complement of isShortRange', () {
      for (final r in BtcRange.values) {
        expect(r.usesAllHistory, !r.isShortRange,
            reason: '${r.name} usesAllHistory mismatch');
      }
    });

    test('btcRangeDays is d1..d7 in declaration order', () {
      expect(btcRangeDays.length, 7);
      expect(btcRangeDays.first, BtcRange.d1);
      expect(btcRangeDays.last, BtcRange.d7);
      for (var i = 0; i < 7; i++) {
        expect(btcRangeDays[i].days, i + 1);
      }
    });

    test('btcRangeWeeks is w1..w4 in declaration order', () {
      expect(btcRangeWeeks.length, 4);
      expect(btcRangeWeeks.first, BtcRange.w1);
      expect(btcRangeWeeks.last, BtcRange.w4);
      for (var i = 0; i < 4; i++) {
        expect(btcRangeWeeks[i].weeks, i + 1);
      }
    });

    test('btcRangeMonths is m1..m12 in declaration order', () {
      expect(btcRangeMonths.length, 12);
      expect(btcRangeMonths.first, BtcRange.m1);
      expect(btcRangeMonths.last, BtcRange.m12);
      for (var i = 0; i < 12; i++) {
        expect(btcRangeMonths[i].months, i + 1);
      }
    });

    test('btcRangeYears is y1..y15 in declaration order', () {
      expect(btcRangeYears.length, 15);
      expect(btcRangeYears.first, BtcRange.y1);
      expect(btcRangeYears.last, BtcRange.y15);
      for (var i = 0; i < 15; i++) {
        expect(btcRangeYears[i].years, i + 1);
      }
    });
  });
}
