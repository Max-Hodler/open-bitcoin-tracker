import 'package:flutter_test/flutter_test.dart';
import 'package:open_bitcoin_tracker/data/app_enums.dart';
import 'package:open_bitcoin_tracker/state/converter_logic.dart';
import 'package:open_bitcoin_tracker/state/converter_state.dart';

void main() {
  group('slotUnit', () {
    test('fiat mode: top is fiat, bottom follows btcMode', () {
      expect(
        slotUnit(ConverterMode.fiat, ConverterSlot.top, BtcDisplayMode.sats),
        ConverterInputUnit.fiat,
      );
      expect(
        slotUnit(ConverterMode.fiat, ConverterSlot.top, BtcDisplayMode.btc),
        ConverterInputUnit.fiat,
      );
      expect(
        slotUnit(ConverterMode.fiat, ConverterSlot.bottom, BtcDisplayMode.sats),
        ConverterInputUnit.sats,
      );
      expect(
        slotUnit(ConverterMode.fiat, ConverterSlot.bottom, BtcDisplayMode.btc),
        ConverterInputUnit.btc,
      );
    });

    test('sats mode: top is sats, bottom is always BTC', () {
      for (final m in BtcDisplayMode.values) {
        expect(
          slotUnit(ConverterMode.sats, ConverterSlot.top, m),
          ConverterInputUnit.sats,
        );
        expect(
          slotUnit(ConverterMode.sats, ConverterSlot.bottom, m),
          ConverterInputUnit.btc,
        );
      }
    });
  });

  group('activeAllowsDecimal', () {
    test('false when active slot resolves to sats; true otherwise', () {
      expect(
        activeAllowsDecimal(
          ConverterMode.sats,
          ConverterSlot.top,
          BtcDisplayMode.btc,
        ),
        isFalse,
      );
      expect(
        activeAllowsDecimal(
          ConverterMode.fiat,
          ConverterSlot.bottom,
          BtcDisplayMode.sats,
        ),
        isFalse,
      );
      expect(
        activeAllowsDecimal(
          ConverterMode.fiat,
          ConverterSlot.top,
          BtcDisplayMode.sats,
        ),
        isTrue,
      );
      expect(
        activeAllowsDecimal(
          ConverterMode.fiat,
          ConverterSlot.bottom,
          BtcDisplayMode.btc,
        ),
        isTrue,
      );
    });
  });

  group('leadingZeroBlocked', () {
    test('true only when sats slot is currently empty', () {
      expect(
        leadingZeroBlocked(
          ConverterMode.sats,
          ConverterSlot.top,
          '',
          BtcDisplayMode.btc,
        ),
        isTrue,
      );
      expect(
        leadingZeroBlocked(
          ConverterMode.fiat,
          ConverterSlot.bottom,
          '',
          BtcDisplayMode.sats,
        ),
        isTrue,
      );
      expect(
        leadingZeroBlocked(
          ConverterMode.sats,
          ConverterSlot.top,
          '5',
          BtcDisplayMode.btc,
        ),
        isFalse,
      );
      expect(
        leadingZeroBlocked(
          ConverterMode.fiat,
          ConverterSlot.top,
          '',
          BtcDisplayMode.sats,
        ),
        isFalse,
      );
    });
  });

  group('insertChar', () {
    test('sats: rejects decimal', () {
      expect(insertChar('123', 3, '.', ConverterInputUnit.sats), isNull);
    });

    test('sats: rejects leading zero on non-empty input', () {
      expect(insertChar('5', 0, '0', ConverterInputUnit.sats), isNull);
    });

    test('sats: allows trailing zero', () {
      expect(insertChar('5', 1, '0', ConverterInputUnit.sats), ('50', 2));
    });

    test('fiat: typing decimal on empty input seeds "0."', () {
      expect(insertChar('', 0, '.', ConverterInputUnit.fiat), ('0.', 2));
    });

    test('fiat: rejects second decimal', () {
      expect(insertChar('1.5', 3, '.', ConverterInputUnit.fiat), isNull);
    });

    test('btc: caps fractional digits at 8', () {
      expect(
        insertChar('0.12345678', 10, '9', ConverterInputUnit.btc),
        isNull,
      );
      expect(
        insertChar('0.1234567', 9, '8', ConverterInputUnit.btc),
        ('0.12345678', 10),
      );
    });

    test('inserts at caret, not just at end', () {
      expect(insertChar('59', 1, '0', ConverterInputUnit.fiat), ('509', 2));
    });
  });

  group('rawToSats / satsToRaw', () {
    const rate = 100000.0; // $100k/BTC keeps the arithmetic obvious.

    test('sats round-trips through itself', () {
      expect(rawToSats('500', ConverterInputUnit.sats, rate), 500);
      expect(satsToRaw(500, ConverterInputUnit.sats, rate), '500');
    });

    test('btc round-trips through sats', () {
      // 0.5 BTC = 50_000_000 sats.
      expect(rawToSats('0.5', ConverterInputUnit.btc, rate), 50000000);
      expect(satsToRaw(50000000, ConverterInputUnit.btc, rate), '0.5');
    });

    test('fiat needs a positive rate', () {
      expect(rawToSats('100', ConverterInputUnit.fiat, 0), 0);
      expect(satsToRaw(50000000, ConverterInputUnit.fiat, 0), '');
    });

    test('zero sats render as empty', () {
      expect(satsToRaw(0, ConverterInputUnit.btc, rate), '');
      expect(satsToRaw(0, ConverterInputUnit.fiat, rate), '');
    });
  });

  group('convertRaw', () {
    const rate = 100000.0;

    test('same unit is identity', () {
      expect(
        convertRaw('1.5', from: ConverterInputUnit.btc, to: ConverterInputUnit.btc, rate: rate),
        '1.5',
      );
    });

    test('empty input is empty', () {
      expect(
        convertRaw('', from: ConverterInputUnit.fiat, to: ConverterInputUnit.btc, rate: rate),
        '',
      );
    });

    test('fiat involved + rate=0 yields empty', () {
      expect(
        convertRaw('1.0', from: ConverterInputUnit.btc, to: ConverterInputUnit.fiat, rate: 0),
        '',
      );
    });

    test('btc↔sats works without a rate', () {
      expect(
        convertRaw('0.001', from: ConverterInputUnit.btc, to: ConverterInputUnit.sats, rate: 0),
        '100000',
      );
    });
  });

  group('deriveRaws', () {
    const rate = 100000.0;

    test('active=top: top is verbatim, bottom is derived', () {
      final r = deriveRaws(
        mode: ConverterMode.sats,
        active: ConverterSlot.top,
        raw: '100000',
        btcMode: BtcDisplayMode.btc,
        rate: rate,
      );
      expect(r.top, '100000');
      expect(r.bottom, '0.001'); // 100k sats = 0.001 BTC
    });

    test('active=bottom: bottom is verbatim, top is derived', () {
      final r = deriveRaws(
        mode: ConverterMode.sats,
        active: ConverterSlot.bottom,
        raw: '0.001',
        btcMode: BtcDisplayMode.btc,
        rate: rate,
      );
      expect(r.top, '100000');
      expect(r.bottom, '0.001');
    });
  });

  group('parseSlot / parseMode / entryFrom', () {
    test('parseSlot accepts canonical names, nullable on unknown', () {
      expect(parseSlot('top'), ConverterSlot.top);
      expect(parseSlot('bottom'), ConverterSlot.bottom);
      expect(parseSlot(null), isNull);
      expect(parseSlot('side'), isNull);
    });

    test('parseMode accepts canonical names, nullable on unknown', () {
      expect(parseMode('fiat'), ConverterMode.fiat);
      expect(parseMode('sats'), ConverterMode.sats);
      expect(parseMode(null), isNull);
      expect(parseMode('bogus'), isNull);
    });

    test('entryFrom places caret at end of raw and defaults slot to top', () {
      final e = entryFrom('12345', null);
      expect(e.raw, '12345');
      expect(e.caret, 5);
      expect(e.active, ConverterSlot.top);
    });

    test('entryFrom honors valid slot codes', () {
      final e = entryFrom('1.5', 'bottom');
      expect(e.active, ConverterSlot.bottom);
      expect(e.caret, 3);
    });
  });
}
