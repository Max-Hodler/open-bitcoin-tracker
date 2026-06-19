import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/l10n/generated/app_localizations.dart';
import 'package:open_bitcoin_tracker/screens/home/home_screen.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:open_bitcoin_tracker/theme/theme.dart';

Future<(Widget, AppStateNotifier)> _wrap(
  WidgetTester tester, {
  String? initialState,
  required VoidCallback onAddStack,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(
    initialState == null ? const {} : {'btc_tracker': initialState},
  );
  final prefs = await SharedPreferences.getInstance();
  final appNotifier = AppStateNotifier(AppStateRepository(prefs));
  final noopHttp = MockClient((_) async => http.Response('', 500));
  final stream = KrakenStreamService();
  final ohlc = KrakenOhlcClient(httpClient: noopHttp);
  final cache = BtcRatesCache(prefs);
  final historyCache = BtcHistoryCache(
    directory: Directory.systemTemp.createTempSync('bt_home_empty_test_'),
  );

  final widget = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appNotifier),
      ChangeNotifierProvider(
        create: (ctx) => StacksLockController(app: appNotifier),
      ),
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
      home: HomeScreen(
        onAddStack: onAddStack,
      ),
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
  return (widget, appNotifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'renders Add Stack button when stacks is empty and triggers callback on tap',
    (tester) async {
      var addStackTapped = false;
      final (w, app) = await _wrap(
        tester,
        onAddStack: () => addStackTapped = true,
      );

      await tester.pumpWidget(w);
      await tester.pump();

      // Verify the button with the label 'Add stack' is rendered.
      final buttonFinder = find.widgetWithText(FilledButton, 'Add stack');
      expect(buttonFinder, findsOneWidget);

      // Verify that the 'Stacks' header is not rendered when empty.
      expect(find.text('Stacks'), findsNothing);

      // Verify background color is grey (surfaceContainer from ColorScheme)
      final button = tester.widget<FilledButton>(buttonFinder);
      final BuildContext context = tester.element(buttonFinder);
      final cs = Theme.of(context).colorScheme;
      expect(button.style?.backgroundColor?.resolve({}), cs.surfaceContainer);

      // Tap the button and verify callback triggers.
      await tester.tap(buttonFinder);
      await tester.pump();

      expect(addStackTapped, isTrue);
    },
  );
}
