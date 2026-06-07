import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Light theme — soft off-white paper page with pure-white card surfaces
  // (the standard grouped-list contrast used by iOS and Material lists).
  static const Color background = Color(0xFFF8F7F3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color mutedSurface = Color(0xFFEEEDE7);

  static const Color bitcoinOrange = Color(0xFFF7931A);
  static const Color bitcoinOrangeTint = Color(0x1AF7931A);

  static const Color priceUp = Color(0xFF4CA66B);
  static const Color priceDown = Color(0xFFC9483B);
  static const Color danger = Color(0xFFB3261E);

  static const Color textPrimary = Color(0xFF1F1B14);
  static const Color textMuted = Color(0xFF6E6A60);

  static const Color divider = Color(0x141F1B14);

  // Dark theme — pure black background with stepped charcoal surfaces.
  static const Color backgroundDark = Color(0xFF000000);
  static const Color mutedSurfaceDark = Color(0xFF1A1A1A);
  static const Color surfaceDark = Color(0xFF1F1F1F);
  // One step *below* mutedSurfaceDark — used for elements that read as
  // recessed against the now-lifted button surfaces (mempool mined blocks,
  // range pills showing past prices). No Material 3 ColorScheme slot fits
  // because surfaceContainerLow is taken by the pure-black scaffold.
  static const Color recessedSurfaceDark = Color(0xFF141414);
  static const Color elevatedSurfaceDark = Color(0xFF262626);

  static const Color bitcoinOrangeDark = Color(0xFFF7A53A);

  static const Color priceUpDark = Color(0xFF56C078);
  static const Color priceDownDark = Color(0xFFE55A4A);
  static const Color dangerDark = Color(0xFFFF5C50);

  static const Color textPrimaryDark = Color(0xFFE6E3DD);
  static const Color textMutedDark = Color(0xFF9A948A);

  static const Color dividerDark = Color(0x24FFFFFF);

  // Dark "Blue" variant — saturated navy in the Monzo dark-theme idiom.
  // Same stepped surface pattern as the black variant; text and divider
  // tokens are shared since they already read well against cool dark surfaces.
  static const Color backgroundDarkBlue = Color(0xFF0F1E3A);
  static const Color mutedSurfaceDarkBlue = Color(0xFF16294A);
  static const Color surfaceDarkBlue = Color(0xFF1A3055);
  static const Color recessedSurfaceDarkBlue = Color(0xFF0B1830);
  static const Color elevatedSurfaceDarkBlue = Color(0xFF1D3559);

  // Light "Pink" variant — the salmon-paper newsprint look used by financial
  // sections (FT, Handelsblatt). Background sits between the FT's #FFF1E5 and
  // a touch warmer to feel less clinical on a phone screen. Text and divider
  // tokens are shared with the cream variant — they're already tuned for
  // warm-paper surfaces.
  static const Color backgroundLightPink = Color(0xFFF7EEE6);
  static const Color surfaceLightPink = Color(0xFFFCF5F0);
  static const Color mutedSurfaceLightPink = Color(0xFFEBDFD6);
}
