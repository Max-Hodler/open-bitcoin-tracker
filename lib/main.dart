import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api.dart';
import 'data/data.dart';
import 'l10n/generated/app_localizations.dart';
import 'screens/home/home_screen.dart';
import 'screens/converter_screen.dart';
import 'screens/new_stack_screens.dart';
import 'services/route_observer.dart';
import 'services/stacks_auth_service.dart';
import 'services/stacks_crypto_service.dart';
import 'services/stacks_unlock_orchestrator.dart';
import 'state/state.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Load symbols for every locale we ship so DateFormat doesn't throw on the
  // first language switch. Cheap (kilobytes), simpler than re-loading on swap.
  await initializeDateFormatting('en_GB');
  await initializeDateFormatting('es_ES');
  final prefs = await SharedPreferences.getInstance();
  runApp(OpenBitcoinTrackerApp(prefs: prefs));
}

class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      onAddStack: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NewStackAmountScreen()),
      ),
      onOpenConverter: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ConverterScreen()),
      ),
    );
  }
}

class OpenBitcoinTrackerApp extends StatelessWidget {
  const OpenBitcoinTrackerApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    final crypto = StacksCryptoService();
    final appRepo = AppStateRepository(prefs, crypto: crypto);
    final ratesCache = BtcRatesCache(prefs);
    final historyCache = BtcHistoryCache();

    return MultiProvider(
      providers: [
        Provider<StacksCryptoService>.value(value: crypto),
        Provider<StacksAuthService>(create: (_) => StacksAuthService()),
        ChangeNotifierProvider(create: (_) => AppStateNotifier(appRepo)),
        ChangeNotifierProvider(
          create: (ctx) =>
              StacksLockController(app: ctx.read<AppStateNotifier>())..start(),
        ),
        ProxyProvider3<AppStateNotifier, StacksAuthService, StacksCryptoService,
            StacksUnlockOrchestrator>(
          update: (_, app, auth, crypto, previous) => StacksUnlockOrchestrator(
            app: app,
            auth: auth,
            crypto: crypto,
          ),
        ),
        ChangeNotifierProvider(create: (_) => ConverterState()),
        ChangeNotifierProvider(
          create: (ctx) {
            final app = ctx.read<AppStateNotifier>();
            final controller = LivePriceController(
              stream: KrakenStreamService(),
              ohlc: KrakenOhlcClient(),
              cache: ratesCache,
              historyCache: historyCache,
              cadence: app.livePriceCadence,
            )..start();
            // Push cadence changes from settings into the controller without
            // recreating the provider. The controller outlives any individual
            // settings change, and only its throttle policy needs to update.
            app.addListener(() {
              controller.cadence = app.livePriceCadence;
            });
            return controller;
          },
        ),
      ],
      // Selecting just the theme/locale fields keeps unrelated state changes
      // (price ranges, stack edits, converter entries…) from re-running the
      // MaterialApp builder at the root.
      child: Selector<AppStateNotifier,
          (LanguagePref, LightVariant, DarkVariant, AppTheme)>(
        selector: (_, app) =>
            (app.language, app.lightVariant, app.darkVariant, app.theme),
        builder: (_, sel, _) {
          final (language, lightVariant, darkVariant, theme) = sel;
          final locale = _localeFor(language) ?? _resolveSystemLocale();
          // Drives Intl.defaultLocale so DateFormat / NumberFormat without an
          // explicit locale render in the user's chosen language. Set on every
          // rebuild so changes via the Settings picker take effect immediately.
          Intl.defaultLocale = locale.toLanguageTag().replaceAll('-', '_');
          return MaterialApp(
          title: 'Open Bitcoin Tracker',
          debugShowCheckedModeBanner: false,
          theme: lightVariant == LightVariant.pink
              ? AppThemes.lightPink()
              : AppThemes.light(),
          darkTheme: darkVariant == DarkVariant.blue
              ? AppThemes.darkBlue()
              : AppThemes.dark(),
          themeMode: theme.themeMode,
          scrollBehavior: noScrollbarsBehavior,
          navigatorObservers: [appRouteObserver],
          locale: locale,
          supportedLocales: const [
            Locale('en', 'GB'),
            Locale('es', 'ES'),
            Locale('pt', 'BR'),
            Locale('ru', 'RU'),
            Locale('tr', 'TR'),
            Locale('vi', 'VN'),
            Locale('ja', 'JP'),
            Locale('fr', 'FR'),
            Locale('de', 'DE'),
            Locale('it', 'IT'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // When AppStateNotifier.language is `system`, locale is null and
          // Flutter resolves the device locale against supportedLocales. The
          // resolver matches device es-* to Locale('es','ES'), en-* (and
          // anything else) to Locale('en','GB') as the documented fallback.
          home: const _HomeShell(),
        );
        },
      ),
    );
  }
}

Locale? _localeFor(LanguagePref pref) {
  switch (pref) {
    case LanguagePref.system:
      return null;
    case LanguagePref.enGB:
      return const Locale('en', 'GB');
    case LanguagePref.esES:
      return const Locale('es', 'ES');
    case LanguagePref.ptBR:
      return const Locale('pt', 'BR');
    case LanguagePref.ruRU:
      return const Locale('ru', 'RU');
    case LanguagePref.trTR:
      return const Locale('tr', 'TR');
    case LanguagePref.viVN:
      return const Locale('vi', 'VN');
    case LanguagePref.jaJP:
      return const Locale('ja', 'JP');
    case LanguagePref.frFR:
      return const Locale('fr', 'FR');
    case LanguagePref.deDE:
      return const Locale('de', 'DE');
    case LanguagePref.itIT:
      return const Locale('it', 'IT');
  }
}

// Map the device locale onto our supported set so Intl uses date symbols
// we've actually loaded. Spanish-speaking devices (any region) get es_ES;
// Portuguese-speaking devices (any region) get pt_BR; Russian-speaking
// devices (any region) get ru_RU; Turkish-speaking devices (any region) get
// tr_TR; Vietnamese-speaking devices (any region) get vi_VN; everything
// else gets en_GB, matching the MaterialApp fallback contract.
Locale _resolveSystemLocale() {
  final system = WidgetsBinding.instance.platformDispatcher.locale;
  if (system.languageCode == 'es') return const Locale('es', 'ES');
  if (system.languageCode == 'pt') return const Locale('pt', 'BR');
  if (system.languageCode == 'ru') return const Locale('ru', 'RU');
  if (system.languageCode == 'tr') return const Locale('tr', 'TR');
  if (system.languageCode == 'vi') return const Locale('vi', 'VN');
  if (system.languageCode == 'ja') return const Locale('ja', 'JP');
  if (system.languageCode == 'fr') return const Locale('fr', 'FR');
  if (system.languageCode == 'de') return const Locale('de', 'DE');
  if (system.languageCode == 'it') return const Locale('it', 'IT');
  return const Locale('en', 'GB');
}
