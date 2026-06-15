import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/l10n/generated/app_localizations.dart';
import 'package:open_bitcoin_tracker/screens/settings_screen.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:open_bitcoin_tracker/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The monolithic SettingsScreen page is gone — settings now live in per-topic
// sub-screens reached from the home-header overflow menu. These tests mount
// each sub-screen directly and assert the behaviour that used to be reached by
// navigating through SettingsScreen.

Future<AppStateNotifier> _notifier({String? initialState}) async {
  SharedPreferences.setMockInitialValues(
    initialState == null ? const {} : {'btc_tracker': initialState},
  );
  final prefs = await SharedPreferences.getInstance();
  return AppStateNotifier(AppStateRepository(prefs));
}

// Wraps a sub-screen in the providers + MaterialApp scaffolding it needs to
// build. Only the providers a given screen reads are required, but supplying
// all of them keeps each test's setup uniform.
Future<Widget> _host(
  WidgetTester tester,
  Widget child, {
  required AppStateNotifier app,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final prefs = await SharedPreferences.getInstance();
  final lock = StacksLockController(app: app);
  addTearDown(lock.dispose);
  final live = LivePriceController(
    stream: KrakenStreamService(),
    ohlc: KrakenOhlcClient(),
    cache: BtcRatesCache(prefs),
    historyCache: BtcHistoryCache(),
  );
  addTearDown(live.dispose);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: lock),
      ChangeNotifierProvider.value(value: live),
    ],
    child: MaterialApp(
      home: child,
      // Theme must be installed so widgets that read the AppPalette extension
      // (`context.palette`) don't crash with "Null check operator used on a
      // null value" — the extension is registered by AppThemes.light().
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

// Drives CurrencyPickerScreen the way the home screen does: push it, let the
// user toggle, then adopt whatever it returns on back into the notifier — so
// the snapping logic in setSelectedCurrencies is exercised end to end.
Future<void> _pumpCurrencyPicker(
  WidgetTester tester,
  AppStateNotifier app,
) async {
  final host = await _host(
    tester,
    Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () async {
            final picked = await Navigator.of(context).push<List<Currency>>(
              MaterialPageRoute(
                builder: (_) =>
                    CurrencyPickerScreen(initial: app.selectedCurrencies),
              ),
            );
            if (picked != null && context.mounted) {
              app.setSelectedCurrencies(picked);
            }
          },
          child: const Text('open'),
        ),
      ),
    ),
    app: app,
  );
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('currency picker lists the available currencies',
      (tester) async {
    final app = await _notifier();
    await _pumpCurrencyPicker(tester, app);

    // Picker tiles use ValueKey('currency-XXX') — proves the picker is mounted.
    expect(find.byKey(const ValueKey('currency-USD')), findsOneWidget);
    expect(find.byKey(const ValueKey('currency-EUR')), findsOneWidget);
  });

  testWidgets('adding EUR via picker extends selection without snapping current',
      (tester) async {
    final app = await _notifier(
      initialState: '{"currency":"USD","selectedCurrencies":["USD"]}',
    );
    await _pumpCurrencyPicker(tester, app);

    await tester.tap(find.byKey(const ValueKey('currency-EUR')));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(app.selectedCurrencies, [Currency.usd, Currency.eur]);
    // Current stays put — adding to the cycle list shouldn't change what's
    // displayed on the home screen.
    expect(app.currency, Currency.usd);
  });

  testWidgets('unchecking the active currency snaps current to first remaining',
      (tester) async {
    final app = await _notifier(
      initialState: '{"currency":"EUR","selectedCurrencies":["USD","EUR"]}',
    );
    await _pumpCurrencyPicker(tester, app);

    await tester.tap(find.byKey(const ValueKey('currency-EUR')));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(app.selectedCurrencies, [Currency.usd]);
    expect(app.currency, Currency.usd);
  });

}
