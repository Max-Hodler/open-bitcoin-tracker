import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bitcoinOrange,
    this.recessedSurface,
  });

  const AppPalette.light()
      : bitcoinOrange = AppColors.bitcoinOrange,
        recessedSurface = null;

  const AppPalette.dark()
      : bitcoinOrange = AppColors.bitcoinOrangeDark,
        recessedSurface = AppColors.recessedSurfaceDark;

  // Blue dark variant reuses the same accent color as the black dark variant —
  // it was tuned for dark surfaces in general, not the specific neutral.
  const AppPalette.darkBlue()
      : bitcoinOrange = AppColors.bitcoinOrangeDark,
        recessedSurface = AppColors.recessedSurfaceDarkBlue;

  // Pink light variant reuses the same accent color as the cream variant —
  // it was tuned for warm light surfaces in general.
  const AppPalette.lightPink()
      : bitcoinOrange = AppColors.bitcoinOrange,
        recessedSurface = null;

  final Color bitcoinOrange;
  // One step *below* the scaffold's lifted button surfaces — used for
  // elements that should read as recessed in dark mode (mempool projected
  // blocks, range pills showing past prices). Null in light mode; callers
  // fall back to `cs.surfaceContainer` there.
  final Color? recessedSurface;

  @override
  AppPalette copyWith({
    Color? bitcoinOrange,
    Color? recessedSurface,
  }) {
    return AppPalette(
      bitcoinOrange: bitcoinOrange ?? this.bitcoinOrange,
      recessedSurface: recessedSurface ?? this.recessedSurface,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bitcoinOrange: Color.lerp(bitcoinOrange, other.bitcoinOrange, t) ?? bitcoinOrange,
      recessedSurface: Color.lerp(recessedSurface, other.recessedSurface, t),
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
