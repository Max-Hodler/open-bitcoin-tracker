import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_enums.dart';
import 'app_colors.dart';
import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

extension AppThemeMode on AppTheme {
  ThemeMode get themeMode {
    switch (this) {
      case AppTheme.light:
        return ThemeMode.light;
      case AppTheme.dark:
        return ThemeMode.dark;
      case AppTheme.system:
        return ThemeMode.system;
    }
  }
}

Color appDialogBarrierColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Colors.black.withValues(alpha: isDark ? 0.7 : 0.4);
}

class AppThemes {
  AppThemes._();

  // Each variant is built from fixed inputs, so build it once and reuse it.
  // The root MaterialApp re-reads these on every AppStateNotifier change;
  // without the memo each read constructs a full Material3 ThemeData just for
  // MaterialApp to deep-compare it equal to the old one.
  static ThemeData? _light;
  static ThemeData? _lightPink;
  static ThemeData? _dark;
  static ThemeData? _darkBlue;

  static ThemeData light() => _light ??= _buildLight();
  static ThemeData lightPink() => _lightPink ??= _buildLightPink();
  static ThemeData dark() => _dark ??= _buildDark();
  static ThemeData darkBlue() => _darkBlue ??= _buildDarkBlue();

  static ThemeData _buildLight() => _build(
        base: ThemeData.light(useMaterial3: true),
        colorScheme: const ColorScheme.light(
          primary: AppColors.bitcoinOrange,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          surfaceContainerLow: AppColors.background,
          surfaceContainer: AppColors.mutedSurface,
          surfaceContainerHigh: Colors.white,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textMuted,
          outlineVariant: AppColors.divider,
          error: AppColors.danger,
          onError: Colors.white,
        ),
        palette: const AppPalette.light(),
        statusBarIconBrightness: Brightness.dark,
        dialogBackgroundColor: AppColors.background,
      );

  static ThemeData _buildLightPink() => _build(
        base: ThemeData.light(useMaterial3: true),
        colorScheme: const ColorScheme.light(
          primary: AppColors.bitcoinOrange,
          onPrimary: Colors.white,
          surface: AppColors.surfaceLightPink,
          surfaceContainerLow: AppColors.backgroundLightPink,
          surfaceContainer: AppColors.mutedSurfaceLightPink,
          surfaceContainerHigh: Colors.white,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textMuted,
          outlineVariant: AppColors.divider,
          error: AppColors.danger,
          onError: Colors.white,
        ),
        palette: const AppPalette.lightPink(),
        statusBarIconBrightness: Brightness.dark,
        dialogBackgroundColor: AppColors.backgroundLightPink,
      );

  static ThemeData _buildDark() => _build(
        base: ThemeData.dark(useMaterial3: true),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.bitcoinOrangeDark,
          onPrimary: Colors.white,
          surface: AppColors.surfaceDark,
          surfaceContainerLow: AppColors.backgroundDark,
          surfaceContainer: AppColors.mutedSurfaceDark,
          surfaceContainerHigh: AppColors.elevatedSurfaceDark,
          onSurface: AppColors.textPrimaryDark,
          onSurfaceVariant: AppColors.textMutedDark,
          outlineVariant: AppColors.dividerDark,
          error: AppColors.dangerDark,
          onError: Colors.white,
        ),
        palette: const AppPalette.dark(),
        statusBarIconBrightness: Brightness.light,
      );

  static ThemeData _buildDarkBlue() => _build(
        base: ThemeData.dark(useMaterial3: true),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.bitcoinOrangeDark,
          onPrimary: Colors.white,
          surface: AppColors.surfaceDarkBlue,
          surfaceContainerLow: AppColors.backgroundDarkBlue,
          surfaceContainer: AppColors.mutedSurfaceDarkBlue,
          surfaceContainerHigh: AppColors.elevatedSurfaceDarkBlue,
          onSurface: AppColors.textPrimaryDark,
          onSurfaceVariant: AppColors.textMutedDark,
          outlineVariant: AppColors.dividerDark,
          error: AppColors.dangerDark,
          onError: Colors.white,
        ),
        palette: const AppPalette.darkBlue(),
        statusBarIconBrightness: Brightness.light,
      );

  static ThemeData _build({
    required ThemeData base,
    required ColorScheme colorScheme,
    required AppPalette palette,
    required Brightness statusBarIconBrightness,
    Color? dialogBackgroundColor,
  }) {
    final radius = BorderRadius.circular(AppSpacing.radius);
    final shape = RoundedRectangleBorder(borderRadius: radius);

    return base.copyWith(
      colorScheme: colorScheme,
      extensions: [palette],
      scaffoldBackgroundColor: colorScheme.surfaceContainerLow,
      canvasColor: colorScheme.surfaceContainerLow,
      dividerColor: colorScheme.outlineVariant,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: base.textTheme
          .copyWith(
            labelSmall: AppTypography.label,
            bodyMedium: AppTypography.body,
            titleMedium: AppTypography.title,
            headlineMedium: AppTypography.display,
          )
          .apply(
            fontFamily: AppTypography.sansFamily,
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.title.copyWith(color: colorScheme.onSurface),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: statusBarIconBrightness,
          statusBarBrightness: statusBarIconBrightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          shape: shape,
          minimumSize: const Size.fromHeight(AppSpacing.stackCardHeight),
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.bitcoinOrange,
          foregroundColor: Colors.white,
          shape: shape,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(AppSpacing.stackCardHeight),
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: palette.bitcoinOrange, width: 1),
        ),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(false),
        thickness: WidgetStatePropertyAll(0),
      ),
      dialogTheme: dialogBackgroundColor == null
          ? null
          : DialogThemeData(backgroundColor: dialogBackgroundColor),
    );
  }
}

class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

const ScrollBehavior noScrollbarsBehavior = _NoScrollbarBehavior();
