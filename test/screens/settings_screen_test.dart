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

Future<(Widget, AppStateNotifier)> _wrap(WidgetTester tester, {String? initialState}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(
    initialState == null ? const {} : {'btc_tracker': initialState},
  );
  final prefs = await SharedPreferences.getInstance();
  final app = AppStateNotifier(AppStateRepository(prefs));
  // StacksSettingsScreen reads StacksLockController via Provider; supply it so
  // tests that navigate into the Stacks sub-screen don't ProviderNotFound.
  final lock = StacksLockController(app: app);
  addTearDown(lock.dispose);
  final widget = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: lock),
    ],
    child: MaterialApp(
      home: const SettingsScreen(),
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
  return (widget, app);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Currencies row opens the currency picker', (tester) async {
    final (w, _) = await _wrap(tester);
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.tap(find.text('Currencies'));
    await tester.pumpAndSettle();

    // Picker tiles use ValueKey('currency-XXX') — proves the picker is mounted.
    expect(find.byKey(const ValueKey('currency-USD')), findsOneWidget);
    expect(find.byKey(const ValueKey('currency-EUR')), findsOneWidget);
  });

  testWidgets('adding EUR via picker extends selection without snapping current',
      (tester) async {
    final (w, app) = await _wrap(
      tester,
      initialState: '{"currency":"USD","selectedCurrencies":["USD"]}',
    );
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.tap(find.text('Currencies'));
    await tester.pumpAndSettle();

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
    final (w, app) = await _wrap(
      tester,
      initialState:
          '{"currency":"EUR","selectedCurrencies":["USD","EUR"]}',
    );
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.tap(find.text('Currencies'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('currency-EUR')));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(app.selectedCurrencies, [Currency.usd]);
    expect(app.currency, Currency.usd);
  });

  testWidgets('Portfolio total tile is hidden when fewer than 2 stacks',
      (tester) async {
    final (w, _) = await _wrap(
      tester,
      initialState: '{"stacks":[{"id":"s1","name":"A","sats":1}]}',
    );
    await tester.pumpWidget(w);
    await tester.pump();

    // Display total lives inside the Stacks sub-screen now — navigate in.
    await tester.tap(find.text('Stacks'));
    await tester.pumpAndSettle();

    expect(find.text('Display total'), findsNothing);
  });

  testWidgets('Portfolio total tile renders and toggles when 2+ stacks',
      (tester) async {
    final (w, app) = await _wrap(
      tester,
      initialState:
          '{"stacks":[{"id":"s1","name":"A","sats":1},{"id":"s2","name":"B","sats":2}]}',
    );
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.tap(find.text('Stacks'));
    await tester.pumpAndSettle();

    expect(find.text('Display total'), findsOneWidget);
    expect(app.showPortfolio, isTrue);

    await tester.tap(find.text('Display total'));
    await tester.pump();
    expect(app.showPortfolio, isFalse);
  });

}
