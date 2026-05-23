import 'dart:io';

import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/l10n/generated/app_localizations.dart';
import 'package:open_bitcoin_tracker/screens/new_stack_screens.dart';
import 'package:open_bitcoin_tracker/widgets/number_pad.dart';
import 'package:open_bitcoin_tracker/widgets/sats_input/sats_input_display.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:open_bitcoin_tracker/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(Widget, AppStateNotifier)> _wrap(WidgetTester tester, {String? initialState}) async {
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
  final historyCache = BtcHistoryCache(directory: Directory.systemTemp.createTempSync('bt_test_'));
  final widget = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appNotifier),
      ChangeNotifierProvider(create: (_) => LivePriceController(stream: stream, ohlc: ohlc, cache: cache, historyCache: historyCache)),
    ],
    child: MaterialApp(
      home: const NewStackAmountScreen(),
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

// SatsInputDisplay renders each digit/separator as its own Text widget so taps
// can place the caret per-glyph; join them back into a single string for
// assertion. Excludes the '₿' symbol Text which is a sibling in the Row.
String _amountText(WidgetTester t) => t
    .widgetList<Text>(find.descendant(
      of: find.byType(SatsInputDisplay),
      matching: find.byType(Text),
    ))
    .map((w) => w.data ?? '')
    .where((s) => s != '₿')
    .join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('confirm advances to name step with the entered amount', (tester) async {
    final (w, app) = await _wrap(tester);
    await tester.pumpWidget(w);

    await tester.tap(find.byKey(numberPadKey('1')));
    await tester.tap(find.byKey(numberPadKey('2')));
    await tester.tap(find.byKey(numberPadKey('3')));
    await tester.pump();

    expect(_amountText(tester), '123');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.byType(NewStackNameScreen), findsOneWidget);
    expect(app.stacks, isEmpty);
  });

  testWidgets('AC clears input', (tester) async {
    final (w, _) = await _wrap(tester);
    await tester.pumpWidget(w);

    await tester.tap(find.byKey(numberPadKey('9')));
    await tester.tap(find.byKey(numberPadKey('9')));
    await tester.pump();
    expect(_amountText(tester), '99');

    await tester.tap(find.byKey(numberPadKey('AC')));
    await tester.pump();
    expect(_amountText(tester), '');
  });

  testWidgets('backspace deletes last digit', (tester) async {
    final (w, _) = await _wrap(tester);
    await tester.pumpWidget(w);

    await tester.tap(find.byKey(numberPadKey('1')));
    await tester.tap(find.byKey(numberPadKey('2')));
    await tester.pump();
    expect(_amountText(tester), '12');

    await tester.tap(find.byKey(numberPadKey('backspace')));
    await tester.pump();
    expect(_amountText(tester), '1');
  });

  testWidgets('confirm is disabled when input is empty', (tester) async {
    final (w, app) = await _wrap(tester);
    await tester.pumpWidget(w);

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(app.stacks, isEmpty);
  });

}
