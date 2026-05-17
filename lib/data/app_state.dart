import '../api/hashrate_client.dart';
import 'app_enums.dart';
import 'stack.dart';

class AppState {
  const AppState({
    this.stacks = const [],
    this.currency = Currency.usd,
    this.selectedCurrencies = const [Currency.usd, Currency.eur, Currency.gbp],
    this.showPortfolio = true,
    this.totalCardAtBottom = true,
    this.showConverterButton = true,
    this.showMempool = true,
    this.showHashrate = true,
    this.showChart = true,
    this.showBtcPrice = true,
    this.theme = AppTheme.system,
    this.darkVariant = DarkVariant.blue,
    this.lightVariant = LightVariant.cream,
    this.btcRange = BtcRange.y10,
    this.overflowQuickRange = BtcRange.y10,
    this.monthsOverflowQuickRange = BtcRange.m1,
    this.hashrateRange = HashrateRange.d3,
    this.logScale = true,
    this.bitcoinDisplayMode = BtcDisplayMode.sats,
    this.stacksAuthMode = StacksAuthMode.off,
    this.stacksLockTimeout = StacksLockTimeout.m1,
    this.language = LanguagePref.system,
    this.livePriceCadence = LivePriceCadence.live,
    this.converterCurrency,
    this.converterBtcMode,
    this.converterMode,
    this.converterFiatModeRaw,
    this.converterFiatModeActiveSlot,
    this.converterSatsModeRaw,
    this.converterSatsModeActiveSlot,
    this.homeWidgetOrder = const [
      HomeWidget.mempoolFees,
      HomeWidget.networkHashrate,
      HomeWidget.stacks,
    ],
  });

  final List<Stack> stacks;
  final Currency currency;
  // Currencies the user has opted into via the picker. Length 1–3, in the
  // order the user checked them — that order is what the home-screen swipe
  // gesture cycles through. Always contains [currency].
  final List<Currency> selectedCurrencies;
  final bool showPortfolio;
  final bool totalCardAtBottom;
  final bool showConverterButton;
  final bool showMempool;
  final bool showHashrate;
  final bool showChart;
  final bool showBtcPrice;
  final AppTheme theme;
  // Which dark palette to apply when the active brightness is dark. Ignored
  // when the resolved theme is light.
  final DarkVariant darkVariant;
  // Symmetric: which light palette to apply when the active brightness is
  // light. Ignored when the resolved theme is dark.
  final LightVariant lightVariant;
  final BtcRange btcRange;
  // The range currently mounted in the overflow quick-chip slot. Long-pressing
  // the overflow chip opens a picker that updates this; tapping it just selects
  // the range like any other quick chip.
  final BtcRange overflowQuickRange;
  // Same idea for the months-overflow chip (1M..12M). Independent slot so the
  // user's months and years selections don't fight each other.
  final BtcRange monthsOverflowQuickRange;
  final HashrateRange hashrateRange;
  final bool logScale;
  // Render satoshi counts as integer sats (default — preserves the unit users
  // entered) or as BTC with up to 8 decimal places. Storage is always sats.
  final BtcDisplayMode bitcoinDisplayMode;
  final StacksAuthMode stacksAuthMode;
  final StacksLockTimeout stacksLockTimeout;
  final LanguagePref language;
  final LivePriceCadence livePriceCadence;
  // Persisted currency for the in-app converter screen. Independent from
  // [currency] (the home-screen / swipe-ring active currency) so the user
  // can convert into a one-off currency without polluting the home view.
  // Null until the user first opens the converter — the screen seeds it
  // from [currency] on that visit.
  final Currency? converterCurrency;
  // Persisted Bitcoin display unit (sats vs BTC) for the converter screen,
  // independent from the global [bitcoinDisplayMode]. Same lifecycle as
  // [converterCurrency]: null until the screen first seeds from the global
  // setting, after which the converter's own picker is the only mutator.
  final BtcDisplayMode? converterBtcMode;
  // Persisted converter mode (fiat↔BTC vs sats↔BTC). Stored as a code
  // ('fiat'/'sats') in JSON. Null defaults to fiat mode on first launch.
  final String? converterMode;
  // Persisted per-mode raw input + active slot for the converter screen so
  // values survive app restarts. Null until the user has typed in that mode.
  // Active slot is stored as a code ('top'/'bottom') in JSON so an unknown
  // value falls back to the default. The raw is locale-neutral ('.'-decimal,
  // no grouping), so the same string parses identically across locales.
  final String? converterFiatModeRaw;
  final String? converterFiatModeActiveSlot;
  final String? converterSatsModeRaw;
  final String? converterSatsModeActiveSlot;
  // Top-to-bottom render order for the home-screen widgets that participate in
  // user reordering. Must contain exactly the set of [HomeWidget.values] —
  // the [fromJson] parser appends missing entries so an upgrade preserves the
  // user's prior ordering while picking up newly-added widgets.
  final List<HomeWidget> homeWidgetOrder;

  AppState copyWith({
    List<Stack>? stacks,
    Currency? currency,
    List<Currency>? selectedCurrencies,
    bool? showPortfolio,
    bool? totalCardAtBottom,
    bool? showConverterButton,
    bool? showMempool,
    bool? showHashrate,
    bool? showChart,
    bool? showBtcPrice,
    AppTheme? theme,
    DarkVariant? darkVariant,
    LightVariant? lightVariant,
    BtcRange? btcRange,
    BtcRange? overflowQuickRange,
    BtcRange? monthsOverflowQuickRange,
    HashrateRange? hashrateRange,
    bool? logScale,
    BtcDisplayMode? bitcoinDisplayMode,
    StacksAuthMode? stacksAuthMode,
    StacksLockTimeout? stacksLockTimeout,
    LanguagePref? language,
    LivePriceCadence? livePriceCadence,
    Currency? converterCurrency,
    BtcDisplayMode? converterBtcMode,
    String? converterMode,
    String? converterFiatModeRaw,
    String? converterFiatModeActiveSlot,
    String? converterSatsModeRaw,
    String? converterSatsModeActiveSlot,
    List<HomeWidget>? homeWidgetOrder,
  }) {
    return AppState(
      stacks: stacks ?? this.stacks,
      currency: currency ?? this.currency,
      selectedCurrencies: selectedCurrencies ?? this.selectedCurrencies,
      showPortfolio: showPortfolio ?? this.showPortfolio,
      totalCardAtBottom: totalCardAtBottom ?? this.totalCardAtBottom,
      showConverterButton: showConverterButton ?? this.showConverterButton,
      showMempool: showMempool ?? this.showMempool,
      showHashrate: showHashrate ?? this.showHashrate,
      showChart: showChart ?? this.showChart,
      showBtcPrice: showBtcPrice ?? this.showBtcPrice,
      theme: theme ?? this.theme,
      darkVariant: darkVariant ?? this.darkVariant,
      lightVariant: lightVariant ?? this.lightVariant,
      btcRange: btcRange ?? this.btcRange,
      overflowQuickRange: overflowQuickRange ?? this.overflowQuickRange,
      monthsOverflowQuickRange:
          monthsOverflowQuickRange ?? this.monthsOverflowQuickRange,
      hashrateRange: hashrateRange ?? this.hashrateRange,
      logScale: logScale ?? this.logScale,
      bitcoinDisplayMode: bitcoinDisplayMode ?? this.bitcoinDisplayMode,
      stacksAuthMode: stacksAuthMode ?? this.stacksAuthMode,
      stacksLockTimeout: stacksLockTimeout ?? this.stacksLockTimeout,
      language: language ?? this.language,
      livePriceCadence: livePriceCadence ?? this.livePriceCadence,
      converterCurrency: converterCurrency ?? this.converterCurrency,
      converterBtcMode: converterBtcMode ?? this.converterBtcMode,
      converterMode: converterMode ?? this.converterMode,
      converterFiatModeRaw: converterFiatModeRaw ?? this.converterFiatModeRaw,
      converterFiatModeActiveSlot: converterFiatModeActiveSlot ??
          this.converterFiatModeActiveSlot,
      converterSatsModeRaw: converterSatsModeRaw ?? this.converterSatsModeRaw,
      converterSatsModeActiveSlot: converterSatsModeActiveSlot ??
          this.converterSatsModeActiveSlot,
      homeWidgetOrder: homeWidgetOrder ?? this.homeWidgetOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'stacks': stacks.map((s) => s.toJson()).toList(),
        'currency': currency.code,
        'selectedCurrencies': [for (final c in selectedCurrencies) c.code],
        'showPortfolio': showPortfolio,
        'totalCardAtBottom': totalCardAtBottom,
        'showConverterButton': showConverterButton,
        'showMempool': showMempool,
        'showHashrate': showHashrate,
        'showChart': showChart,
        'showBtcPrice': showBtcPrice,
        'theme': theme.code,
        'darkVariant': darkVariant.code,
        'lightVariant': lightVariant.code,
        'btcRange': btcRange.code,
        'overflowQuickRange': overflowQuickRange.code,
        'monthsOverflowQuickRange': monthsOverflowQuickRange.code,
        'hashrateRange': hashrateRange.code,
        'logScale': logScale,
        'bitcoinDisplayMode': bitcoinDisplayMode.code,
        'stacksAuthMode': stacksAuthMode.code,
        'stacksLockTimeout': stacksLockTimeout.code,
        'language': language.code,
        'livePriceCadence': livePriceCadence.code,
        if (converterCurrency != null) 'converterCurrency': converterCurrency!.code,
        if (converterBtcMode != null) 'converterBtcMode': converterBtcMode!.code,
        if (converterMode != null) 'converterMode': converterMode,
        if (converterFiatModeRaw != null)
          'converterFiatModeRaw': converterFiatModeRaw,
        if (converterFiatModeActiveSlot != null)
          'converterFiatModeActiveSlot': converterFiatModeActiveSlot,
        if (converterSatsModeRaw != null)
          'converterSatsModeRaw': converterSatsModeRaw,
        if (converterSatsModeActiveSlot != null)
          'converterSatsModeActiveSlot': converterSatsModeActiveSlot,
        'homeWidgetOrder': [for (final w in homeWidgetOrder) w.code],
      };

  factory AppState.fromJson(Map<String, dynamic> json) {
    final rawStacks = json['stacks'];
    final stacks = rawStacks is List
        ? rawStacks.map(Stack.fromJson).whereType<Stack>().toList()
        : const <Stack>[];

    // Reads json[key] as a nullable String and forwards it to fromCode. Every
    // enum's fromCode returns its own documented default when the input is
    // null or unknown, so missing/garbage keys don't need handling here.
    T fromCode<T>(String key, T Function(String?) parse) =>
        parse(json[key] as String?);

    final currency = fromCode('currency', Currency.fromCode);
    final selectedCurrencies =
        _parseSelectedCurrencies(json['selectedCurrencies'], currency);

    return AppState(
      stacks: stacks,
      currency: currency,
      selectedCurrencies: selectedCurrencies,
      showPortfolio: json['showPortfolio'] as bool? ?? true,
      totalCardAtBottom: json['totalCardAtBottom'] as bool? ?? true,
      showConverterButton: json['showConverterButton'] as bool? ?? true,
      showMempool: json['showMempool'] as bool? ?? true,
      showHashrate: json['showHashrate'] as bool? ?? true,
      showChart: json['showChart'] as bool? ?? true,
      showBtcPrice: json['showBtcPrice'] as bool? ?? true,
      theme: fromCode('theme', AppTheme.fromCode),
      darkVariant: fromCode('darkVariant', DarkVariant.fromCode),
      lightVariant: fromCode('lightVariant', LightVariant.fromCode),
      btcRange: fromCode('btcRange', BtcRange.fromCode),
      // The overflow chips are special-cased: a missing key (vs. a wrong code)
      // means "the user has never opened the picker", and we want that to land
      // on the menu's default slot, not on BtcRange.fromCode's general default.
      overflowQuickRange: json['overflowQuickRange'] is String
          ? BtcRange.fromCode(json['overflowQuickRange'] as String)
          : BtcRange.y10,
      monthsOverflowQuickRange: json['monthsOverflowQuickRange'] is String
          ? BtcRange.fromCode(json['monthsOverflowQuickRange'] as String)
          : BtcRange.m1,
      hashrateRange: fromCode('hashrateRange', HashrateRange.fromCode),
      logScale: json['logScale'] as bool? ?? true,
      bitcoinDisplayMode:
          fromCode('bitcoinDisplayMode', BtcDisplayMode.fromCode),
      stacksAuthMode: fromCode('stacksAuthMode', StacksAuthMode.fromCode),
      stacksLockTimeout:
          fromCode('stacksLockTimeout', StacksLockTimeout.fromCode),
      language: fromCode('language', LanguagePref.fromCode),
      livePriceCadence:
          fromCode('livePriceCadence', LivePriceCadence.fromCode),
      // Nullable: legacy installs and fresh ones both produce null; the
      // converter screen seeds from [currency] on its first opened visit.
      // Unknown codes also fall to null rather than silently snapping to USD.
      converterCurrency: switch (json['converterCurrency']) {
        final String code => Currency.values
            .where((c) => c.code == code)
            .cast<Currency?>()
            .firstWhere((_) => true, orElse: () => null),
        _ => null,
      },
      // Same null-friendly read as [converterCurrency]: unknown / missing
      // codes leave the field null so the converter seeds from the global
      // setting on its next visit.
      converterBtcMode: switch (json['converterBtcMode']) {
        final String code => BtcDisplayMode.values
            .where((m) => m.code == code)
            .cast<BtcDisplayMode?>()
            .firstWhere((_) => true, orElse: () => null),
        _ => null,
      },
      converterMode: json['converterMode'] as String?,
      converterFiatModeRaw: json['converterFiatModeRaw'] as String?,
      converterFiatModeActiveSlot:
          json['converterFiatModeActiveSlot'] as String?,
      converterSatsModeRaw: json['converterSatsModeRaw'] as String?,
      converterSatsModeActiveSlot:
          json['converterSatsModeActiveSlot'] as String?,
      homeWidgetOrder: _parseHomeWidgetOrder(json['homeWidgetOrder']),
    );
  }

  // Pre-existing installs won't have `selectedCurrencies` in their JSON; fall
  // back to a single-element list of the active currency so the swipe gesture
  // opens the picker (the documented 1-element behavior) until they pick more.
  static List<Currency> _parseSelectedCurrencies(
    Object? raw,
    Currency fallbackCurrent,
  ) {
    if (raw is! List) return [fallbackCurrent];
    final out = <Currency>[];
    for (final item in raw) {
      if (item is! String) continue;
      // Skip unknown codes rather than silently coercing to the fallback —
      // `Currency.fromCode` would otherwise turn every garbage entry into a
      // duplicate of `fallbackCurrent`.
      final match = Currency.values
          .where((c) => c.code == item)
          .cast<Currency?>()
          .firstWhere((_) => true, orElse: () => null);
      if (match == null) continue;
      if (!out.contains(match)) out.add(match);
      if (out.length == 3) break;
    }
    if (out.isEmpty) return [fallbackCurrent];
    if (!out.contains(fallbackCurrent)) {
      // The persisted current currency must be in the cycle list so the swipe
      // gesture can find it. Drop the last entry to make room if needed.
      if (out.length == 3) out.removeLast();
      out.insert(0, fallbackCurrent);
    }
    return out;
  }

  // Parses [HomeWidget] codes from JSON, preserving the user's order while
  // filling in any enum values missing from the persisted list. Removed enum
  // values get silently dropped (fromCode returns null for unknown codes).
  // Newly-added values are appended at the end.
  static List<HomeWidget> _parseHomeWidgetOrder(Object? raw) {
    const fallback = [
      HomeWidget.mempoolFees,
      HomeWidget.networkHashrate,
      HomeWidget.stacks,
    ];
    if (raw is! List) return fallback;
    final out = <HomeWidget>[];
    for (final item in raw) {
      if (item is! String) continue;
      final match = HomeWidget.fromCode(item);
      if (match == null) continue;
      if (!out.contains(match)) out.add(match);
    }
    for (final w in HomeWidget.values) {
      if (out.contains(w)) continue;
      out.add(w);
    }
    return out;
  }
}

