import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  static const String sansFamily = 'Inter';
  static const String monoFamily = 'JetBrainsMono';

  static const TextStyle label = TextStyle(
    fontFamily: sansFamily,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0.6,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle body = TextStyle(
    fontFamily: sansFamily,
    fontSize: 14,
    height: 1.4,
  );

  static const TextStyle title = TextStyle(
    fontFamily: sansFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle display = TextStyle(
    fontFamily: sansFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFamily,
    fontSize: 16,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
