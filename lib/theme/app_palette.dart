import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bitcoinOrange,
    required this.priceUp,
    required this.priceDown,
    this.recessedSurface,
  });

  const AppPalette.light()
      : bitcoinOrange = AppColors.bitcoinOrange,
        priceUp = AppColors.priceUp,
        priceDown = AppColors.priceDown,
        recessedSurface = null;

  const AppPalette.dark()
      : bitcoinOrange = AppColors.bitcoinOrangeDark,
        priceUp = AppColors.priceUpDark,
        priceDown = AppColors.priceDownDark,
        recessedSurface = AppColors.recessedSurfaceDark;

  // Blue dark variant reuses the same accent + price colors as the black
  // dark variant — they were tuned for dark surfaces in general, not the
  // specific neutral.
  const AppPalette.darkBlue()
      : bitcoinOrange = AppColors.bitcoinOrangeDark,
        priceUp = AppColors.priceUpDark,
        priceDown = AppColors.priceDownDark,
        recessedSurface = AppColors.recessedSurfaceDarkBlue;

  // Pink light variant reuses the same accent + price colors as the cream
  // variant — they were tuned for warm light surfaces in general.
  const AppPalette.lightPink()
      : bitcoinOrange = AppColors.bitcoinOrange,
        priceUp = AppColors.priceUp,
        priceDown = AppColors.priceDown,
        recessedSurface = null;

  final Color bitcoinOrange;
  final Color priceUp;
  final Color priceDown;
  // One step *below* the scaffold's lifted button surfaces — used for
  // elements that should read as recessed in dark mode (mempool projected
  // blocks, range pills showing past prices). Null in light mode; callers
  // fall back to `cs.surfaceContainer` there.
  final Color? recessedSurface;

  @override
  AppPalette copyWith({
    Color? bitcoinOrange,
    Color? priceUp,
    Color? priceDown,
    Color? recessedSurface,
  }) {
    return AppPalette(
      bitcoinOrange: bitcoinOrange ?? this.bitcoinOrange,
      priceUp: priceUp ?? this.priceUp,
      priceDown: priceDown ?? this.priceDown,
      recessedSurface: recessedSurface ?? this.recessedSurface,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bitcoinOrange: Color.lerp(bitcoinOrange, other.bitcoinOrange, t) ?? bitcoinOrange,
      priceUp: Color.lerp(priceUp, other.priceUp, t) ?? priceUp,
      priceDown: Color.lerp(priceDown, other.priceDown, t) ?? priceDown,
      recessedSurface: Color.lerp(recessedSurface, other.recessedSurface, t),
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
