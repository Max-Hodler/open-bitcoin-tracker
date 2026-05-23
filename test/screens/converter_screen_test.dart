import 'dart:io';

import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/l10n/generated/app_localizations.dart';
import 'package:open_bitcoin_tracker/screens/converter_screen.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:open_bitcoin_tracker/theme/theme.dart';
import 'package:open_bitcoin_tracker/widgets/number_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _keypadKey(String label) => find.byKey(numberPadKey(label));

Future<Widget> _wrap() async {
  SharedPreferences.setMockInitialValues({
    'btc_rates_cache': '{"USD":100000,"GBP":80000,"EUR":90000}',
  });
  final prefs = await SharedPreferences.getInstance();
  final app = AppStateNotifier(AppStateRepository(prefs));
  final noopHttp = MockClient((_) async => http.Response('', 500));
  final stream = KrakenStreamService();
  final ohlc = KrakenOhlcClient(httpClient: noopHttp);
  final cache = BtcRatesCache(prefs);
  final historyCache = BtcHistoryCache(directory: Directory.systemTemp.createTempSync('bt_test_'));
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => ConverterState()),
      ChangeNotifierProvider(create: (_) => LivePriceController(stream: stream, ohlc: ohlc, cache: cache, historyCache: historyCache)),
    ],
    child: MaterialApp(
      home: const ConverterScreen(),
      theme: AppThemes.light(),
      locale: const Locale('en', 'GB'),
      supportedLocales: const [Locale('en', 'GB'), Locale('es', 'ES')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

// The active converter card renders its value as a Text.rich with per-char
// TextSpan recognizers (so taps can place the caret); find.text won't match
// the combined span. This finder matches either a plain Text or a Text.rich
// whose flattened plain text — with WidgetSpan placeholder chars (U+FFFC)
// from the caret stripped — equals [expected].
Finder _findValueText(String expected) => find.byWidgetPredicate((w) {
      if (w is Text) {
        if (w.data == expected) return true;
        final span = w.textSpan;
        if (span == null) return false;
        final flat = span.toPlainText().replaceAll('￼', '');
        return flat == expected;
      }
      return false;
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders empty default state', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    // The old rate-label line ('1 BTC = $100,000') was removed when the
    // converter dropped its static rate display; assert the scaffold instead.
    expect(find.text('Fiat - BTC'), findsOneWidget);
    expect(find.text('Sats - BTC'), findsOneWidget);
    expect(find.text('BITCOIN (SATS)'), findsOneWidget);
    expect(find.byType(NumberPad), findsOneWidget);
  });

  testWidgets('typing a fiat digit computes sats', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    await tester.tap(_keypadKey('5'));
    await tester.pump();

    // fiat = 5 -> 5,000 sats on sats card
    expect(_findValueText('5,000'), findsOneWidget);
  });

  testWidgets('switching to sats then typing computes BTC', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    await tester.tap(find.text('Sats - BTC'));
    await tester.pump();

    // In sats mode both slots are bitcoin units (sats <-> BTC). Type
    // 100,000,000 sats and confirm the other slot reads 1 BTC.
    await tester.tap(_keypadKey('1'));
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.tap(_keypadKey('0'));
      await tester.pump();
    }

    expect(_findValueText('100,000,000'), findsOneWidget);
    // BITCOIN (BTC) slot label confirms which card the "1" belongs to.
    expect(find.text('BITCOIN (BTC)'), findsOneWidget);
    expect(_findValueText('1'), findsWidgets);
  });

  testWidgets('decimal key only available in fiat mode', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    expect(_keypadKey('.'), findsOneWidget);
    expect(_keypadKey('AC'), findsNothing);

    await tester.tap(find.text('Sats - BTC'));
    await tester.pump();

    expect(_keypadKey('.'), findsNothing);
    expect(_keypadKey('AC'), findsOneWidget);
  });
}
