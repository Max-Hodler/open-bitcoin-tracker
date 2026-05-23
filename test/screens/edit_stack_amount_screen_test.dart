import 'dart:io';

import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/l10n/generated/app_localizations.dart';
import 'package:open_bitcoin_tracker/screens/edit_stack_screens.dart';
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

Future<(Widget, AppStateNotifier)> _wrap(WidgetTester tester, {required String initialState}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'btc_tracker': initialState});
  final prefs = await SharedPreferences.getInstance();
  final app = AppStateNotifier(AppStateRepository(prefs));
  // EditStackAmountScreen reads StacksLockController in initState to pop home
  // when the stacks re-lock mid-edit; supply one so the test doesn't
  // ProviderNotFound.
  final lock = StacksLockController(app: app);
  addTearDown(lock.dispose);
  final noopHttp = MockClient((_) async => http.Response('', 500));
  final stream = KrakenStreamService();
  final ohlc = KrakenOhlcClient(httpClient: noopHttp);
  final cache = BtcRatesCache(prefs);
  final historyCache = BtcHistoryCache(directory: Directory.systemTemp.createTempSync('bt_test_'));
  final widget = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: lock),
      ChangeNotifierProvider(create: (_) => LivePriceController(stream: stream, ohlc: ohlc, cache: cache, historyCache: historyCache)),
    ],
    child: MaterialApp(
      home: const EditStackAmountScreen(stackId: 's1'),
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

  testWidgets('prefills input with existing sats', (tester) async {
    final (w, _) = await _wrap(
      tester,
      initialState: '{"stacks":[{"id":"s1","name":"A","sats":12345}]}',
    );
    await tester.pumpWidget(w);
    await tester.pump();

    expect(_amountText(tester), '12,345');
  });

  testWidgets('confirm updates sats without changing name', (tester) async {
    final (w, app) = await _wrap(
      tester,
      initialState: '{"stacks":[{"id":"s1","name":"Cold","sats":1000}]}',
    );
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.tap(find.byKey(numberPadKey('AC')));
    await tester.pump();
    await tester.tap(find.byKey(numberPadKey('9')));
    await tester.tap(find.byKey(numberPadKey('9')));
    await tester.pump();

    await tester.tap(find.text('Update amount'));
    await tester.pump();

    final s = app.stacks.single;
    expect(s.id, 's1');
    expect(s.name, 'Cold');
    expect(s.sats, 99);
  });

  testWidgets('cancel discards edits', (tester) async {
    final (w, app) = await _wrap(
      tester,
      initialState: '{"stacks":[{"id":"s1","name":"A","sats":500}]}',
    );
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.tap(find.byKey(numberPadKey('AC')));
    await tester.pump();
    await tester.tap(find.byKey(numberPadKey('7')));
    await tester.pump();

    expect(app.stacks.single.sats, 500);
  });
}
