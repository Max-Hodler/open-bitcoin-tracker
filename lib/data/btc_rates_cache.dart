import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_enums.dart';

class BtcRates {
  const BtcRates({
    this.usd,
    this.gbp,
    this.eur,
    this.jpy,
    this.cad,
    this.aud,
    this.chf,
  });

  final double? usd;
  final double? gbp;
  final double? eur;
  final double? jpy;
  final double? cad;
  final double? aud;
  final double? chf;

  double? forCurrency(Currency c) => switch (c) {
        Currency.usd => usd,
        Currency.gbp => gbp,
        Currency.eur => eur,
        Currency.jpy => jpy,
        Currency.cad => cad,
        Currency.aud => aud,
        Currency.chf => chf,
      };

  // Standard `?? this.field` copyWith: can update a field but not reset it to
  // null. That's fine for the tick-merge path, which only ever sets a new
  // price; no caller needs to clear a rate.
  BtcRates copyWith({
    double? usd,
    double? gbp,
    double? eur,
    double? jpy,
    double? cad,
    double? aud,
    double? chf,
  }) =>
      BtcRates(
        usd: usd ?? this.usd,
        gbp: gbp ?? this.gbp,
        eur: eur ?? this.eur,
        jpy: jpy ?? this.jpy,
        cad: cad ?? this.cad,
        aud: aud ?? this.aud,
        chf: chf ?? this.chf,
      );

  Map<String, dynamic> toJson() => {
        if (usd != null) 'USD': usd,
        if (gbp != null) 'GBP': gbp,
        if (eur != null) 'EUR': eur,
        if (jpy != null) 'JPY': jpy,
        if (cad != null) 'CAD': cad,
        if (aud != null) 'AUD': aud,
        if (chf != null) 'CHF': chf,
      };

  factory BtcRates.fromJson(Map<String, dynamic> json) => BtcRates(
        usd: (json['USD'] as num?)?.toDouble(),
        gbp: (json['GBP'] as num?)?.toDouble(),
        eur: (json['EUR'] as num?)?.toDouble(),
        jpy: (json['JPY'] as num?)?.toDouble(),
        cad: (json['CAD'] as num?)?.toDouble(),
        aud: (json['AUD'] as num?)?.toDouble(),
        chf: (json['CHF'] as num?)?.toDouble(),
      );
}

class BtcRatesCache {
  BtcRatesCache(this._prefs);

  static const String storageKey = 'btc_rates_cache';

  final SharedPreferences _prefs;

  BtcRates load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const BtcRates();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return BtcRates.fromJson(decoded);
    } on FormatException {
      // Treat malformed JSON as empty per STORAGE.md.
    }
    return const BtcRates();
  }

  Future<void> save(BtcRates rates) async {
    await _prefs.setString(storageKey, jsonEncode(rates.toJson()));
  }
}
