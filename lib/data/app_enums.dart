enum Currency {
  // Majors first (matches Coinbase/Kraken/Stripe convention — most users want
  // one of these three), then alphabetical for the rest.
  usd('USD'),
  eur('EUR'),
  gbp('GBP'),
  aud('AUD'),
  cad('CAD'),
  chf('CHF'),
  jpy('JPY');

  const Currency(this.code);
  final String code;

  static Currency fromCode(String? code, {Currency fallback = Currency.usd}) {
    for (final c in Currency.values) {
      if (c.code == code) return c;
    }
    return fallback;
  }
}

// Whether Bitcoin amounts are rendered as integer satoshis (the canonical
// storage unit) or as BTC with up to 8 decimal places. Affects every amount
// readout in the UI — stack cards, portfolio total.
enum BtcDisplayMode {
  sats,
  btc;

  String get code => name;

  static BtcDisplayMode fromCode(String? code) {
    for (final m in BtcDisplayMode.values) {
      if (m.code == code) return m;
    }
    return BtcDisplayMode.btc;
  }
}

enum AppTheme {
  system,
  light,
  dark;

  String get code => name;

  static AppTheme fromCode(String? code) {
    for (final t in AppTheme.values) {
      if (t.code == code) return t;
    }
    return AppTheme.system;
  }
}

// Which palette to use when the active brightness is dark. Independent of
// [AppTheme] so the user can pair "Blue" with either "Dark" (always blue) or
// "System" (follows OS — blue only when the device goes dark).
enum DarkVariant {
  blue,
  black;

  String get code => name;

  static DarkVariant fromCode(String? code) {
    for (final v in DarkVariant.values) {
      if (v.code == code) return v;
    }
    return DarkVariant.blue;
  }
}

// Light-mode counterpart of [DarkVariant]. `cream` is the original warm-paper
// look; `pink` is a newsprint-finance section variant.
enum LightVariant {
  cream,
  pink;

  String get code => name;

  static LightVariant fromCode(String? code) {
    for (final v in LightVariant.values) {
      if (v.code == code) return v;
    }
    return LightVariant.cream;
  }
}

enum BtcRange {
  d1('1D'),
  d2('2D'),
  d3('3D'),
  d4('4D'),
  d5('5D'),
  d6('6D'),
  d7('7D'),
  w1('1W'),
  w2('2W'),
  w3('3W'),
  w4('4W'),
  m1('1M'),
  m2('2M'),
  m3('3M'),
  m4('4M'),
  m5('5M'),
  m6('6M'),
  m7('7M'),
  m8('8M'),
  m9('9M'),
  m10('10M'),
  m11('11M'),
  m12('12M'),
  y1('1Y'),
  y2('2Y'),
  y3('3Y'),
  y4('4Y'),
  y5('5Y'),
  y6('6Y'),
  y7('7Y'),
  y8('8Y'),
  y9('9Y'),
  y10('10Y'),
  y11('11Y'),
  y12('12Y'),
  y13('13Y'),
  y14('14Y'),
  y15('15Y'),
  all('All');

  const BtcRange(this.code);
  final String code;

  static BtcRange fromCode(String? code) {
    for (final r in BtcRange.values) {
      if (r.code == code) return r;
    }
    return BtcRange.y10;
  }

  // Number of days this range represents, or null if it isn't day-shaped.
  int? get days {
    switch (this) {
      case BtcRange.d1: return 1;
      case BtcRange.d2: return 2;
      case BtcRange.d3: return 3;
      case BtcRange.d4: return 4;
      case BtcRange.d5: return 5;
      case BtcRange.d6: return 6;
      case BtcRange.d7: return 7;
      default: return null;
    }
  }

  // Number of weeks this range represents, or null if it isn't week-shaped.
  int? get weeks {
    switch (this) {
      case BtcRange.w1: return 1;
      case BtcRange.w2: return 2;
      case BtcRange.w3: return 3;
      case BtcRange.w4: return 4;
      default: return null;
    }
  }

  // Number of months this range represents, or null if it isn't month-shaped.
  // (m1..m12 → 1..12; everything else → null.)
  int? get months {
    switch (this) {
      case BtcRange.m1: return 1;
      case BtcRange.m2: return 2;
      case BtcRange.m3: return 3;
      case BtcRange.m4: return 4;
      case BtcRange.m5: return 5;
      case BtcRange.m6: return 6;
      case BtcRange.m7: return 7;
      case BtcRange.m8: return 8;
      case BtcRange.m9: return 9;
      case BtcRange.m10: return 10;
      case BtcRange.m11: return 11;
      case BtcRange.m12: return 12;
      default: return null;
    }
  }

  // Number of years this range represents, or null otherwise.
  int? get years {
    switch (this) {
      case BtcRange.y1: return 1;
      case BtcRange.y2: return 2;
      case BtcRange.y3: return 3;
      case BtcRange.y4: return 4;
      case BtcRange.y5: return 5;
      case BtcRange.y6: return 6;
      case BtcRange.y7: return 7;
      case BtcRange.y8: return 8;
      case BtcRange.y9: return 9;
      case BtcRange.y10: return 10;
      case BtcRange.y11: return 11;
      case BtcRange.y12: return 12;
      case BtcRange.y13: return 13;
      case BtcRange.y14: return 14;
      case BtcRange.y15: return 15;
      default: return null;
    }
  }

  bool get isDays => days != null;
  bool get isWeeks => weeks != null;
  bool get isMonths => months != null;
  bool get isYears => years != null;

  // The d1..d7 / w1..w4 / m1 ranges that come from Kraken's intraday OHLC
  // endpoint (per-minute or per-hour candles, single trailing window).
  // Everything else is served from the full daily history series.
  bool get isShortRange => isDays || isWeeks || this == BtcRange.m1;

  // Whether the chart draws against the full FX history series rather than a
  // recent OHLC window. Complement of [isShortRange].
  bool get usesAllHistory => !isShortRange;
}

// Stable, sorted lists for each overflow slot's candidates.
final List<BtcRange> btcRangeDays =
    BtcRange.values.where((r) => r.isDays).toList(growable: false);
final List<BtcRange> btcRangeWeeks =
    BtcRange.values.where((r) => r.isWeeks).toList(growable: false);
final List<BtcRange> btcRangeMonths =
    BtcRange.values.where((r) => r.isMonths).toList(growable: false);
final List<BtcRange> btcRangeYears =
    BtcRange.values.where((r) => r.isYears).toList(growable: false);

enum StacksAuthMode {
  off('off'),
  device('device'),
  pin('pin');

  const StacksAuthMode(this.code);
  final String code;

  static StacksAuthMode fromCode(String? code) {
    for (final m in StacksAuthMode.values) {
      if (m.code == code) return m;
    }
    return StacksAuthMode.off;
  }
}

enum LanguagePref {
  system('system'),
  enGB('en_GB'),
  esES('es_ES'),
  ptBR('pt_BR'),
  ruRU('ru_RU'),
  trTR('tr_TR'),
  viVN('vi_VN'),
  jaJP('ja_JP'),
  frFR('fr_FR'),
  deDE('de_DE'),
  itIT('it_IT');

  const LanguagePref(this.code);
  final String code;

  static LanguagePref fromCode(String? code) {
    for (final l in LanguagePref.values) {
      if (l.code == code) return l;
    }
    return LanguagePref.system;
  }
}

// How often the live BTC price card is allowed to repaint. Tied directly to a
// throttle on `notifyListeners()` in [LivePriceController]; the WS keeps
// streaming regardless so the cached rate stays warm and currency-swipe stays
// instant.
enum LivePriceCadence {
  live('live', null),
  s5('5s', Duration(seconds: 5)),
  s15('15s', Duration(seconds: 15));

  const LivePriceCadence(this.code, this.minInterval);

  final String code;
  // null for `live` (no minimum repaint interval).
  final Duration? minInterval;

  static LivePriceCadence fromCode(String? code) {
    for (final c in LivePriceCadence.values) {
      if (c.code == code) return c;
    }
    return LivePriceCadence.live;
  }
}

enum StacksLockTimeout {
  s30('30s', Duration(seconds: 30)),
  m1('1m', Duration(minutes: 1)),
  m5('5m', Duration(minutes: 5)),
  never('never', null);

  const StacksLockTimeout(this.code, this.duration);
  final String code;
  final Duration? duration;

  static StacksLockTimeout fromCode(String? code) {
    for (final t in StacksLockTimeout.values) {
      if (t.code == code) return t;
    }
    return StacksLockTimeout.m1;
  }
}

enum ChartHeight {
  m('xs', 204),
  l('s', 272),
  xl('m', 340),
  xxl('l', 408),
  xxxl('xl', 476);

  const ChartHeight(this.code, this.px);
  final String code;

  /// Rendered pixel height of the chart area for this setting.
  final double px;

  static ChartHeight fromCode(String? code) {
    for (final h in ChartHeight.values) {
      if (h.code == code) return h;
    }
    return ChartHeight.xxxl;
  }
}

// Home-screen widgets that participate in user-defined ordering. The price
// header / chart are structurally fixed and not represented here.
enum HomeWidget {
  stacks('stacks');

  const HomeWidget(this.code);
  final String code;

  static HomeWidget? fromCode(String? code) {
    for (final w in HomeWidget.values) {
      if (w.code == code) return w;
    }
    return null;
  }
}
