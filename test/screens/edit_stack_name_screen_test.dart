import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:open_bitcoin_tracker/l10n/generated/app_localizations.dart';
import 'package:open_bitcoin_tracker/screens/edit_stack_screens.dart';
import 'package:open_bitcoin_tracker/state/state.dart';
import 'package:open_bitcoin_tracker/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(Widget, AppStateNotifier)> _wrap({required String stackId}) async {
  SharedPreferences.setMockInitialValues(const {
    'btc_tracker':
        '{"stacks":[{"id":"s1","name":"Cold","sats":100}]}',
  });
  final prefs = await SharedPreferences.getInstance();
  final app = AppStateNotifier(AppStateRepository(prefs));
  // EditStackNameScreen reads StacksLockController in initState to pop home
  // when the stacks re-lock mid-edit; supply one so the test doesn't
  // ProviderNotFound.
  final lock = StacksLockController(app: app);
  addTearDown(lock.dispose);
  final widget = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: lock),
    ],
    child: MaterialApp(
      home: EditStackNameScreen(stackId: stackId),
      // AppPalette extension is registered by AppThemes.light(); without it,
      // `context.palette` null-throws on first paint.
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

  testWidgets('prefills with the current name uppercased', (tester) async {
    final (w, _) = await _wrap(stackId: 's1');
    await tester.pumpWidget(w);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'COLD');
  });

  testWidgets('confirm saves trimmed name and pops', (tester) async {
    final (_, app) = await _wrap(stackId: 's1');
    final lock = StacksLockController(app: app);
    addTearDown(lock.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemes.light(),
      locale: const Locale('en', 'GB'),
      supportedLocales: const [Locale('en', 'GB'), Locale('es', 'ES')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: app),
              ChangeNotifierProvider.value(value: lock),
            ],
            child: const EditStackNameScreen(stackId: 's1'),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '  Warm wallet  ');
    await tester.tap(find.text('Change name'));
    await tester.pump();

    expect(app.stacks.single.name, 'WARM WALLET');
  });

  testWidgets('confirm is disabled when input is empty after trim', (tester) async {
    final (w, app) = await _wrap(stackId: 's1');
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    await tester.tap(find.text('Change name'));
    await tester.pump();

    expect(app.stacks.single.name, 'Cold');
  });

  testWidgets('limit label appears at 24 chars', (tester) async {
    final (w, _) = await _wrap(stackId: 's1');
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'x' * 24);
    await tester.pump(const Duration(milliseconds: 200));

    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1.0);
  });

  testWidgets('input is capped at 24 characters', (tester) async {
    final (w, _) = await _wrap(stackId: 's1');
    await tester.pumpWidget(w);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'y' * 40);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 24);
  });
}
