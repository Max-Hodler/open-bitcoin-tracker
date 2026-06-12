import '../api/hashrate_client.dart';
import 'app_enums.dart';
import 'stack.dart';

class AppState {
  const AppState({
    this.stacks = const [],
    this.currency = Currency.usd,
    this.selectedCurrencies = const [Currency.usd, Currency.eur, Currency.gbp],
    this.showPortfolio = true,
    this.showMempool = false,
    this.mempoolBlocksReversed = false,
    this.showHashrate = false,
    this.showChart = true,
    this.chartHeight = ChartHeight.xl,
    this.theme = AppTheme.system,
    this.darkVariant = DarkVariant.blue,
    this.lightVariant = LightVariant.cream,
    this.btcRange = BtcRange.all,
    this.daysOverflowQuickRange = BtcRange.d1,
    this.weeksOverflowQuickRange = BtcRange.w1,
    this.overflowQuickRange = BtcRange.y10,
    this.monthsOverflowQuickRange = BtcRange.m6,
    this.hashrateRange = HashrateRange.d3,
    this.logScale = true,
    this.btcDisplayMode = BtcDisplayMode.sats,
    this.stacksAuthMode = StacksAuthMode.off,
    this.stacksLockTimeout = StacksLockTimeout.m5,
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
    this.totalImageData,
    this.totalColorKey,
    this.changePillsHintDismissed = false,
    this.rangeChipHintDismissed = false,
    this.swipeChipHintDismissed = false,
    this.showPriceDelta = false,
  });

  final List<Stack> stacks;
  final Currency currency;
  // Currencies the user has opted into via the picker. Length 1–3, in the
  // order the user checked them — that order is what the home-screen swipe
  // gesture cycles through. Always contains [currency].
  final List<Currency> selectedCurrencies;
  final bool showPortfolio;
  final bool showMempool;
  // When true, mirror the mempool block strip so mined blocks appear on the
  // left and projected blocks on the right (default has projected on the
  // left and mined on the right). Order within each group is also reversed
  // so the time arrow flows consistently across the divider.
  final bool mempoolBlocksReversed;
  final bool showHashrate;
  final bool showChart;
  final ChartHeight chartHeight;
  final AppTheme theme;
  // Which dark palette to apply when the active brightness is dark. Ignored
  // when the resolved theme is light.
  final DarkVariant darkVariant;
  // Symmetric: which light palette to apply when the active brightness is
  // light. Ignored when the resolved theme is dark.
  final LightVariant lightVariant;
  final BtcRange btcRange;
  // The range mounted in the days overflow chip (1D..7D).
  final BtcRange daysOverflowQuickRange;
  // The range mounted in the weeks overflow chip (1W..4W).
  final BtcRange weeksOverflowQuickRange;
  // The range currently mounted in the years overflow quick-chip slot.
  final BtcRange overflowQuickRange;
  // Same idea for the months-overflow chip (1M..12M).
  final BtcRange monthsOverflowQuickRange;
  final HashrateRange hashrateRange;
  final bool logScale;
  // Render satoshi counts as integer sats (default — preserves the unit users
  // entered) or as BTC with up to 8 decimal places. Storage is always sats.
  final BtcDisplayMode btcDisplayMode;
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
  // independent from the global [btcDisplayMode]. Same lifecycle as
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
  // Avatar customization for the portfolio total card — same shape as the
  // per-stack [Stack.imageData] / [Stack.colorKey] fields. The total card
  // isn't a Stack so its avatar settings live here on AppState. Null means
  // default initial-letter circle in the theme's bitcoinOrange.
  final String? totalImageData;
  final String? totalColorKey;
  // True once the user dismisses the one-time hint that explains revealing the
  // range/change pills by swiping a stack card aside. Persisted so the hint
  // never reappears on later launches, even after more stacks are added.
  final bool changePillsHintDismissed;
  // True once the user long-presses any range chip for the first time, or the
  // hint text is dismissed. The hint sits below the chip row and teaches that
  // long-pressing opens the range picker for that chip slot.
  final bool rangeChipHintDismissed;
  // True once the user swipes up or down on any range chip for the first time.
  // The hint (shown after [rangeChipHintDismissed]) teaches the swipe-to-cycle
  // shortcut. Shown only after the long-press hint has been dismissed.
  final bool swipeChipHintDismissed;
  // When true, show the signed tick-to-tick price delta as a subtitle below
  // the live price for ~2 s each time the price updates. Off by default.
  final bool showPriceDelta;
  AppState copyWith({
    List<Stack>? stacks,
    Currency? currency,
    List<Currency>? selectedCurrencies,
    bool? showPortfolio,
    bool? showMempool,
    bool? mempoolBlocksReversed,
    bool? showHashrate,
    bool? showChart,
    ChartHeight? chartHeight,
    AppTheme? theme,
    DarkVariant? darkVariant,
    LightVariant? lightVariant,
    BtcRange? btcRange,
    BtcRange? daysOverflowQuickRange,
    BtcRange? weeksOverflowQuickRange,
    BtcRange? overflowQuickRange,
    BtcRange? monthsOverflowQuickRange,
    HashrateRange? hashrateRange,
    bool? logScale,
    BtcDisplayMode? btcDisplayMode,
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
    String? totalImageData,
    bool clearTotalImage = false,
    String? totalColorKey,
    bool clearTotalColor = false,
    bool? changePillsHintDismissed,
    bool? rangeChipHintDismissed,
    bool? swipeChipHintDismissed,
    bool? showPriceDelta,
  }) {
    return AppState(
      stacks: stacks ?? this.stacks,
      currency: currency ?? this.currency,
      selectedCurrencies: selectedCurrencies ?? this.selectedCurrencies,
      showPortfolio: showPortfolio ?? this.showPortfolio,
      showMempool: showMempool ?? this.showMempool,
      mempoolBlocksReversed:
          mempoolBlocksReversed ?? this.mempoolBlocksReversed,
      showHashrate: showHashrate ?? this.showHashrate,
      showChart: showChart ?? this.showChart,
      chartHeight: chartHeight ?? this.chartHeight,
      theme: theme ?? this.theme,
      darkVariant: darkVariant ?? this.darkVariant,
      lightVariant: lightVariant ?? this.lightVariant,
      btcRange: btcRange ?? this.btcRange,
      daysOverflowQuickRange:
          daysOverflowQuickRange ?? this.daysOverflowQuickRange,
      weeksOverflowQuickRange:
          weeksOverflowQuickRange ?? this.weeksOverflowQuickRange,
      overflowQuickRange: overflowQuickRange ?? this.overflowQuickRange,
      monthsOverflowQuickRange:
          monthsOverflowQuickRange ?? this.monthsOverflowQuickRange,
      hashrateRange: hashrateRange ?? this.hashrateRange,
      logScale: logScale ?? this.logScale,
      btcDisplayMode: btcDisplayMode ?? this.btcDisplayMode,
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
      totalImageData: clearTotalImage
          ? null
          : (totalImageData ?? this.totalImageData),
      totalColorKey: clearTotalColor
          ? null
          : (totalColorKey ?? this.totalColorKey),
      changePillsHintDismissed:
          changePillsHintDismissed ?? this.changePillsHintDismissed,
      rangeChipHintDismissed:
          rangeChipHintDismissed ?? this.rangeChipHintDismissed,
      swipeChipHintDismissed:
          swipeChipHintDismissed ?? this.swipeChipHintDismissed,
      showPriceDelta: showPriceDelta ?? this.showPriceDelta,
    );
  }

  Map<String, dynamic> toJson() => {
        'stacks': stacks.map((s) => s.toJson()).toList(),
        'currency': currency.code,
        'selectedCurrencies': [for (final c in selectedCurrencies) c.code],
        'showPortfolio': showPortfolio,
        'showMempool': showMempool,
        'mempoolBlocksReversed': mempoolBlocksReversed,
        'showHashrate': showHashrate,
        'showChart': showChart,
        'chartHeight': chartHeight.code,
        'theme': theme.code,
        'darkVariant': darkVariant.code,
        'lightVariant': lightVariant.code,
        'btcRange': btcRange.code,
        'daysOverflowQuickRange': daysOverflowQuickRange.code,
        'weeksOverflowQuickRange': weeksOverflowQuickRange.code,
        'overflowQuickRange': overflowQuickRange.code,
        'monthsOverflowQuickRange': monthsOverflowQuickRange.code,
        'hashrateRange': hashrateRange.code,
        'logScale': logScale,
        'bitcoinDisplayMode': btcDisplayMode.code,
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
        if (totalImageData != null) 'totalImageData': totalImageData,
        if (totalColorKey != null) 'totalColorKey': totalColorKey,
        'changePillsHintDismissed': changePillsHintDismissed,
        'rangeChipHintDismissed': rangeChipHintDismissed,
        'swipeChipHintDismissed': swipeChipHintDismissed,
        'showPriceDelta': showPriceDelta,
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
      showMempool: json['showMempool'] as bool? ?? true,
      mempoolBlocksReversed: json['mempoolBlocksReversed'] as bool? ?? false,
      showHashrate: json['showHashrate'] as bool? ?? false,
      showChart: json['showChart'] as bool? ?? true,
      chartHeight: ChartHeight.fromCode(json['chartHeight'] as String?),
      theme: fromCode('theme', AppTheme.fromCode),
      darkVariant: fromCode('darkVariant', DarkVariant.fromCode),
      lightVariant: fromCode('lightVariant', LightVariant.fromCode),
      // btcRange is special-cased like the overflow chips: a missing key means
      // first launch, so land on the intended default (all) rather than
      // BtcRange.fromCode's general fallback (y10).
      btcRange: json['btcRange'] is String
          ? BtcRange.fromCode(json['btcRange'] as String)
          : BtcRange.all,
      // The overflow chips are special-cased: a missing key (vs. a wrong code)
      // means "the user has never opened the picker", so land on the default
      // slot rather than BtcRange.fromCode's general default.
      daysOverflowQuickRange: json['daysOverflowQuickRange'] is String
          ? BtcRange.fromCode(json['daysOverflowQuickRange'] as String)
          : BtcRange.d1,
      weeksOverflowQuickRange: json['weeksOverflowQuickRange'] is String
          ? BtcRange.fromCode(json['weeksOverflowQuickRange'] as String)
          : BtcRange.w1,
      overflowQuickRange: json['overflowQuickRange'] is String
          ? BtcRange.fromCode(json['overflowQuickRange'] as String)
          : BtcRange.y10,
      monthsOverflowQuickRange: json['monthsOverflowQuickRange'] is String
          ? BtcRange.fromCode(json['monthsOverflowQuickRange'] as String)
          : BtcRange.m6,
      hashrateRange: fromCode('hashrateRange', HashrateRange.fromCode),
      logScale: json['logScale'] as bool? ?? true,
      btcDisplayMode:
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
      totalImageData: json['totalImageData'] is String
          ? json['totalImageData'] as String
          : null,
      totalColorKey: json['totalColorKey'] is String
          ? json['totalColorKey'] as String
          : null,
      changePillsHintDismissed:
          json['changePillsHintDismissed'] as bool? ?? false,
      rangeChipHintDismissed:
          json['rangeChipHintDismissed'] as bool? ?? false,
      swipeChipHintDismissed:
          json['swipeChipHintDismissed'] as bool? ?? false,
      showPriceDelta: json['showPriceDelta'] as bool? ?? false,
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

