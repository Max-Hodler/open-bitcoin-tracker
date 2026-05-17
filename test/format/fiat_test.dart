import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/format/fiat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatFiat', () {
    test('rounds to integer with thousands separators', () {
      final r = formatFiat(1234567.89, Currency.usd);
      expect(r.symbol, r'$');
      expect(r.amount, '1,234,568');
      expect(r.full, r'$1,234,568');
    });

    test('picks symbol per currency', () {
      expect(formatFiat(100, Currency.gbp).symbol, '£');
      expect(formatFiat(100, Currency.eur).symbol, '€');
    });
  });

  group('formatBtcAmount', () {
    test('prefixes with ₿ and formats sats', () {
      expect(formatBtcAmount(100000000), '₿100,000,000');
    });

    test('masks when hidden', () {
      expect(formatBtcAmount(1, hidden: true), '**** **** ****');
    });
  });
}
