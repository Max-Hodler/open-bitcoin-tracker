import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppState', () {
    test('defaults match STORAGE.md', () {
      const s = AppState();
      expect(s.stacks, isEmpty);
      expect(s.currency, Currency.usd);
      expect(s.showPortfolio, true);

      expect(s.theme, AppTheme.system);
      expect(s.btcRange, BtcRange.all);
      expect(s.logScale, true);
    });

    test('empty json hydrates to defaults', () {
      final s = AppState.fromJson(const {});
      expect(s.currency, Currency.usd);
      expect(s.btcRange, BtcRange.all);
      expect(s.logScale, true);
    });

    test('invalid btcRange falls back to default (10Y)', () {
      final s = AppState.fromJson(const {'btcRange': 'bogus'});
      expect(s.btcRange, BtcRange.y10);
    });

    test('round-trips through JSON', () {
      const original = AppState(
        stacks: [
          Stack(id: 'a', name: 'Cold', sats: 100000000),
          Stack(id: 'b', name: 'Hot', sats: 50000, isHidden: true),
        ],
        currency: Currency.eur,
        btcRange: BtcRange.y1,
        logScale: false,
      );
      final roundTripped = AppState.fromJson(
        Map<String, dynamic>.from(original.toJson()),
      );
      expect(roundTripped.stacks.length, 2);
      expect(roundTripped.stacks[0].name, 'Cold');
      expect(roundTripped.stacks[1].isHidden, true);
      expect(roundTripped.currency, Currency.eur);
      expect(roundTripped.btcRange, BtcRange.y1);
      expect(roundTripped.logScale, false);
    });

    test('stack with missing fields is dropped', () {
      final s = AppState.fromJson(const {
        'stacks': [
          {'id': 'ok', 'name': 'A', 'sats': 1},
          {'id': 'bad'}, // missing name/sats
          'not-a-map',
        ],
      });
      expect(s.stacks.length, 1);
      expect(s.stacks.first.id, 'ok');
    });

    test('total avatar fields default to null and are omitted from JSON', () {
      const s = AppState();
      expect(s.totalImageData, isNull);
      expect(s.totalColorKey, isNull);
      final json = s.toJson();
      expect(json.containsKey('totalImageData'), isFalse);
      expect(json.containsKey('totalColorKey'), isFalse);
    });

    test('totalImageData / totalColorKey round-trip through JSON', () {
      const original = AppState(
        totalImageData: 'AAAB',
        totalColorKey: 'rust',
      );
      final restored = AppState.fromJson(
        Map<String, dynamic>.from(original.toJson()),
      );
      expect(restored.totalImageData, 'AAAB');
      expect(restored.totalColorKey, 'rust');
    });

    test('fromJson ignores non-string total avatar fields', () {
      final s = AppState.fromJson(const {
        'totalImageData': 42,
        'totalColorKey': true,
      });
      expect(s.totalImageData, isNull);
      expect(s.totalColorKey, isNull);
    });

    test('copyWith(clearTotalImage: true) nulls totalImageData', () {
      const s = AppState(totalImageData: 'AAAB');
      expect(s.copyWith(clearTotalImage: true).totalImageData, isNull);
    });

    test('copyWith(clearTotalColor: true) nulls totalColorKey', () {
      const s = AppState(totalColorKey: 'amber');
      expect(s.copyWith(clearTotalColor: true).totalColorKey, isNull);
    });

    test('copyWith(clearTotalImage:) wins over totalImageData arg', () {
      const s = AppState(totalImageData: 'AAAB');
      expect(
        s.copyWith(totalImageData: 'BBBC', clearTotalImage: true).totalImageData,
        isNull,
      );
    });
  });

  group('Sats', () {
    test('conversion is symmetric', () {
      expect(Sats.toBtc(Sats.perBtc), 1.0);
      expect(Sats.fromBtc(2.5), 250000000);
    });

    test('toFiat multiplies BTC value by rate', () {
      expect(Sats.toFiat(Sats.perBtc, 50000), 50000);
      expect(Sats.toFiat(Sats.perBtc ~/ 2, 50000), 25000);
    });
  });
}
