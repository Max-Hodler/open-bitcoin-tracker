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
// readout in the UI — stack cards, portfolio total, mempool total-fees row.
enum BtcDisplayMode {
  sats,
  btc;

  String get code => name;

  static BtcDisplayMode fromCode(String? code) {
    for (final m in BtcDisplayMode.values) {
      if (m.code == code) return m;
    }
    return BtcDisplayMode.sats;
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
  w1('1W'),
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
  ytd('YTD'),
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
}

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
  s15('15s', Duration(seconds: 15)),
  off('off', null);

  const LivePriceCadence(this.code, this.minInterval);

  final String code;
  // null for `live` (no minimum) and for `off` (notifications suppressed
  // entirely — the gate runs before any interval check).
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

// Home-screen widgets that participate in user-defined ordering. The price
// header / chart are structurally fixed and not represented here.
enum HomeWidget {
  stacks('stacks'),
  mempoolFees('mempoolFees'),
  networkHashrate('networkHashrate');

  const HomeWidget(this.code);
  final String code;

  static HomeWidget? fromCode(String? code) {
    for (final w in HomeWidget.values) {
      if (w.code == code) return w;
    }
    return null;
  }
}
