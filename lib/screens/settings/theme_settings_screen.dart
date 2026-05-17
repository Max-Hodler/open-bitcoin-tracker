import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import '_widgets.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    // Light/Dark style rows are only meaningful when the active resolved theme
    // renders that brightness. With the opposite mode forced, dim the rows so
    // users can see the option exists but understand it's not in effect.
    final darkStyleEnabled = app.theme != AppTheme.light;
    final lightStyleEnabled = app.theme != AppTheme.dark;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.onSurfaceVariant),
        centerTitle: true,
        title: Text(
          l10n.settingsThemeLabel,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: ScrollHairline(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl * 2,
          ),
          children: [
            for (final t in AppTheme.values) ...[
              SettingsRadioRowTile<AppTheme>(
                label: _themeOptionLabel(l10n, t),
                value: t,
                groupValue: app.theme,
                onChanged: app.setTheme,
              ),
              if (t != AppTheme.values.last)
                const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, thickness: 1, color: cs.outlineVariant),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
              child: Text(
                l10n.settingsLightStyleLabel,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: lightStyleEnabled
                      ? cs.onSurfaceVariant
                      : cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            for (final v in LightVariant.values) ...[
              SettingsRadioRowTile<LightVariant>(
                label: _lightVariantLabel(l10n, v),
                value: v,
                groupValue: app.lightVariant,
                onChanged: app.setLightVariant,
                enabled: lightStyleEnabled,
              ),
              if (v != LightVariant.values.last)
                const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, thickness: 1, color: cs.outlineVariant),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
              child: Text(
                l10n.settingsDarkStyleLabel,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: darkStyleEnabled
                      ? cs.onSurfaceVariant
                      : cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            for (final v in DarkVariant.values) ...[
              SettingsRadioRowTile<DarkVariant>(
                label: _darkVariantLabel(l10n, v),
                value: v,
                groupValue: app.darkVariant,
                onChanged: app.setDarkVariant,
                enabled: darkStyleEnabled,
              ),
              if (v != DarkVariant.values.last)
                const SizedBox(height: AppSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }
}

String _themeOptionLabel(AppLocalizations l10n, AppTheme theme) {
  switch (theme) {
    case AppTheme.system:
      return l10n.themeOptionSystem;
    case AppTheme.light:
      return l10n.themeOptionLight;
    case AppTheme.dark:
      return l10n.themeOptionDark;
  }
}

String _darkVariantLabel(AppLocalizations l10n, DarkVariant v) {
  switch (v) {
    case DarkVariant.black:
      return l10n.darkStyleOptionBlack;
    case DarkVariant.blue:
      return l10n.darkStyleOptionBlue;
  }
}

String _lightVariantLabel(AppLocalizations l10n, LightVariant v) {
  switch (v) {
    case LightVariant.cream:
      return l10n.lightStyleOptionCream;
    case LightVariant.pink:
      return l10n.lightStyleOptionPink;
  }
}
