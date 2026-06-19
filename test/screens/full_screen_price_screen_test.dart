import 'dart:io';

import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/l10n/generated/app_localizations.dart';
import 'package:open_bitcoin_tracker/screens/full_screen_price/full_screen_price_screen.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:open_bitcoin_tracker/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _wrap({
  required DarkVariant darkVariant,
  required AppTheme theme,
}) async {
  SharedPreferences.setMockInitialValues({
    'btc_rates_cache': '{"USD":100000,"GBP":80000,"EUR":90000}',
  });
  final prefs = await SharedPreferences.getInstance();
  final app = AppStateNotifier(AppStateRepository(prefs));
  app.setDarkVariant(darkVariant);
  app.setTheme(theme);

  final noopHttp = MockClient((_) async => http.Response('', 500));
  final stream = KrakenStreamService();
  final ohlc = KrakenOhlcClient(httpClient: noopHttp);
  final cache = BtcRatesCache(prefs);
  final historyCache = BtcHistoryCache(directory: Directory.systemTemp.createTempSync('bt_test_'));

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(
        create: (_) => LivePriceController(
          stream: stream,
          ohlc: ohlc,
          cache: cache,
          historyCache: historyCache,
        ),
      ),
    ],
    child: MaterialApp(
      home: const FullScreenPriceScreen(currency: Currency.usd),
      theme: AppThemes.light(),
      darkTheme: darkVariant == DarkVariant.blue
          ? AppThemes.darkBlue()
          : AppThemes.dark(),
      themeMode: theme.themeMode,
      locale: const Locale('en', 'GB'),
      supportedLocales: const [Locale('en', 'GB')],
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

  testWidgets('background is pure black in OLED black theme', (tester) async {
    // OLED Black corresponds to dark theme with DarkVariant.black
    await tester.pumpWidget(await _wrap(
      darkVariant: DarkVariant.black,
      theme: AppTheme.dark,
    ));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);

    await tester.pump(AppStateNotifier.saveDebounceWindow);
  });

  testWidgets('background is surfaceDarkBlue in Dark Blue theme', (tester) async {
    await tester.pumpWidget(await _wrap(
      darkVariant: DarkVariant.blue,
      theme: AppTheme.dark,
    ));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.surfaceDarkBlue);

    await tester.pump(AppStateNotifier.saveDebounceWindow);
  });

  testWidgets('background is surface (pure white) in Light theme', (tester) async {
    await tester.pumpWidget(await _wrap(
      darkVariant: DarkVariant.black,
      theme: AppTheme.light,
    ));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.surface);

    await tester.pump(AppStateNotifier.saveDebounceWindow);
  });
}
