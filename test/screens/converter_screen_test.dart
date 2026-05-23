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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders empty default state with rate label', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    expect(find.text('1 BTC = \$100,000'), findsOneWidget);
  });

  testWidgets('typing a fiat digit computes sats', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    await tester.tap(_keypadKey('5'));
    await tester.pump();

    // fiat = 5 -> 5,000 sats on sats card
    expect(find.text('5,000'), findsOneWidget);
  });

  testWidgets('switching to sats then typing computes fiat', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    await tester.tap(find.text('BITCOIN'));
    await tester.pump();

    // Type 100000000 sats = 1 BTC -> 100,000 fiat.
    await tester.tap(_keypadKey('1'));
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.tap(_keypadKey('0'));
      await tester.pump();
    }

    expect(find.text('100,000,000'), findsOneWidget);
    expect(find.text('100,000.00'), findsOneWidget);
  });

  testWidgets('decimal key only available in fiat mode', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pump();

    expect(_keypadKey('.'), findsOneWidget);
    expect(_keypadKey('AC'), findsNothing);

    await tester.tap(find.text('BITCOIN'));
    await tester.pump();

    expect(_keypadKey('.'), findsNothing);
    expect(_keypadKey('AC'), findsOneWidget);
  });
}
