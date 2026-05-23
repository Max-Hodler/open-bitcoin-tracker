import 'package:flutter_test/flutter_test.dart';
import 'package:open_bitcoin_tracker/data/sats.dart';

void main() {
  group('Sats.satsToBtcRaw / btcRawToSats', () {
    test('round-trips canonical values', () {
      expect(Sats.satsToBtcRaw(0), '');
      expect(Sats.satsToBtcRaw(1), '0.00000001');
      expect(Sats.satsToBtcRaw(100000000), '1');
      expect(Sats.satsToBtcRaw(150000000), '1.5');
      expect(Sats.satsToBtcRaw(Sats.maxSupply), '21000000');
    });

    test('trims trailing zeros in the fractional part', () {
      expect(Sats.satsToBtcRaw(50000000), '0.5');
      expect(Sats.satsToBtcRaw(50000), '0.0005');
    });

    test('btcRawToSats parses bare integers and decimals', () {
      expect(Sats.btcRawToSats(''), 0);
      expect(Sats.btcRawToSats('0'), 0);
      expect(Sats.btcRawToSats('1'), 100000000);
      expect(Sats.btcRawToSats('1.5'), 150000000);
      expect(Sats.btcRawToSats('0.00000001'), 1);
    });

    test('btcRawToSats returns 0 on unparseable input', () {
      expect(Sats.btcRawToSats('abc'), 0);
      expect(Sats.btcRawToSats('1.2.3'), 0);
    });
  });

  group('Sats.tryInsertBtcChar', () {
    test('first decimal seeds "0."', () {
      expect(Sats.tryInsertBtcChar('', 0, '.'), ('0.', 2));
    });

    test('second decimal is rejected', () {
      expect(Sats.tryInsertBtcChar('1.5', 3, '.'), isNull);
    });

    test('caps fractional digits at 8', () {
      expect(Sats.tryInsertBtcChar('0.12345678', 10, '9'), isNull);
      expect(
        Sats.tryInsertBtcChar('0.1234567', 9, '8'),
        ('0.12345678', 10),
      );
    });

    test('rejects values past the 21M supply', () {
      // 21_000_001 BTC must not slip through.
      expect(Sats.tryInsertBtcChar('2100000', 7, '1'), isNull);
    });

    test('accepts the exact 21M cap', () {
      expect(
        Sats.tryInsertBtcChar('2100000', 7, '0'),
        ('21000000', 8),
      );
    });

    test('blocks a leading 0 on a non-zero integer part', () {
      expect(Sats.tryInsertBtcChar('5', 0, '0'), isNull);
    });

    test('allows a leading 0 when current value already starts with 0', () {
      expect(Sats.tryInsertBtcChar('0.5', 0, '0'), ('00.5', 1));
    });
  });

  group('Sats.sanitizePastedSats', () {
    test('strips non-digits and leading zeros', () {
      expect(Sats.sanitizePastedSats('  123,456 sats '), '123456');
      expect(Sats.sanitizePastedSats('000123'), '123');
    });

    test('returns null for empty / zero / overflow / over-supply', () {
      expect(Sats.sanitizePastedSats(''), isNull);
      expect(Sats.sanitizePastedSats('abc'), isNull);
      expect(Sats.sanitizePastedSats('000'), isNull);
      expect(Sats.sanitizePastedSats('999999999999999999999'), isNull);
    });

    test('rejects values above max supply', () {
      // maxSupply + 1
      final tooMany = (Sats.maxSupply + 1).toString();
      expect(Sats.sanitizePastedSats(tooMany), isNull);
    });
  });

  group('Sats.sanitizePastedBtc', () {
    test('en-US style: "1,234.56" → 1234.56', () {
      expect(Sats.sanitizePastedBtc('1,234.56'), '1234.56');
    });

    test('es-ES style: "1.234,56" → 1234.56', () {
      expect(Sats.sanitizePastedBtc('1.234,56'), '1234.56');
    });

    test('strips currency symbols and whitespace', () {
      expect(Sats.sanitizePastedBtc('₿ 0.5'), '0.5');
    });

    test('trims trailing zeros via sats round-trip', () {
      // 0.50000000 → 50_000_000 sats → '0.5'
      expect(Sats.sanitizePastedBtc('0.50000000'), '0.5');
    });

    test('rejects zero, empty, and over-supply', () {
      expect(Sats.sanitizePastedBtc(''), isNull);
      expect(Sats.sanitizePastedBtc('0'), isNull);
      expect(Sats.sanitizePastedBtc('21000001'), isNull);
    });

    test('picks the LAST separator as the decimal point', () {
      // "1.2,3,4" — last comma is the decimal point; earlier separators are
      // grouping noise. So integer part "1.2,3" → strip seps → "123",
      // fractional part "4" → final "123.4".
      expect(Sats.sanitizePastedBtc('1.2,3,4'), '123.4');
    });
  });
}
