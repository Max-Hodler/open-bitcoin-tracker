import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_enums.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../state/state.dart';
import '../theme/theme.dart';
import '../widgets/scroll_hairline.dart';
import 'about_screen.dart';
import 'settings/settings_widgets.dart';
import 'settings/btc_price_settings_screen.dart';
import 'settings/mempool_blocks_settings_screen.dart';
import 'settings/reorder_home_widgets_screen.dart';
import 'settings/stacks_settings_screen.dart';
import 'settings/theme_settings_screen.dart';

// Re-export the public sub-screen classes so external callers (main.dart,
// home_screen.dart, settings_screen_test.dart) can keep importing this single
// file without caring how the package is laid out internally.
export 'settings/btc_price_settings_screen.dart' show BtcPriceSettingsScreen;
export 'settings/currency_picker_screen.dart' show CurrencyPickerScreen;
export 'settings/lock_stacks_settings_screen.dart'
    show LockStacksSettingsScreen;
export 'settings/mempool_blocks_settings_screen.dart'
    show MempoolBlocksSettingsScreen;
export 'settings/reorder_home_widgets_screen.dart'
    show ReorderHomeWidgetsScreen;
export 'settings/stacks_settings_screen.dart' show StacksSettingsScreen;
export 'settings/theme_settings_screen.dart' show ThemeSettingsScreen;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.onSurfaceVariant),
        centerTitle: true,
        title: Text(
          l10n.settingsTitle,
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
            SettingsGroup(
              children: [
                SettingsPickerTile(
                  label: l10n.settingsLanguageLabel,
                  value: '',
                  onTap: () => _openLanguagePicker(context, app),
                  trailingIcon: Icons.unfold_more,
                ),
                SettingsSegmentedTile(
                  label: l10n.settingsBitcoinDisplayMode,
                  options: [
                    l10n.bitcoinDisplayModeSats,
                    l10n.bitcoinDisplayModeBtc,
                  ],
                  selectedIndex:
                      app.bitcoinDisplayMode == BtcDisplayMode.btc ? 1 : 0,
                  enabled: true,
                  onChanged: (i) => app.setBitcoinDisplayMode(
                    i == 1 ? BtcDisplayMode.btc : BtcDisplayMode.sats,
                  ),
                ),
                SettingsPickerTile(
                  label: l10n.settingsThemeLabel,
                  value: '',
                  onTap: () => _openThemeScreen(context),
                  trailingIcon: Icons.chevron_right,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsGroup(
              children: [
                SettingsPickerTile(
                  label: l10n.settingsBtcPrice,
                  value: '',
                  onTap: () => _openBtcPriceSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsPickerTile(
                  label: l10n.settingsGroupPrivacy,
                  value: '',
                  onTap: () => _openStacksSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsPickerTile(
                  label: l10n.settingsMempoolWidget,
                  value: '',
                  onTap: () => _openMempoolBlocksSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsToggleTile(
                  label: l10n.settingsHashrateWidget,
                  value: app.showHashrate,
                  enabled: true,
                  onChanged: app.setShowHashrate,
                ),
                SettingsToggleTile(
                  label: l10n.settingsConverterButton,
                  value: app.showConverterButton,
                  enabled: true,
                  onChanged: app.setShowConverterButton,
                ),
                SettingsPickerTile(
                  label: l10n.settingsReorderWidgets,
                  value: '',
                  onTap: () => _openReorderWidgetsSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsGroup(
              children: [
                SettingsPickerTile(
                  label: l10n.settingsAbout,
                  value: '',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsActionTile(
                  label: l10n.settingsResetAllOptions,
                  onTap: () => _confirmReset(context, app),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLanguagePicker(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    final picked = await _showLanguagePicker(context, app.language);
    if (picked != null) app.setLanguage(picked);
  }

  void _openThemeScreen(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ThemeSettingsScreen()),
    );
  }

  void _openBtcPriceSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BtcPriceSettingsScreen()),
    );
  }

  void _openStacksSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const StacksSettingsScreen()),
    );
  }

  void _openMempoolBlocksSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MempoolBlocksSettingsScreen(),
      ),
    );
  }

  void _openReorderWidgetsSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ReorderHomeWidgetsScreen(),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, AppStateNotifier app) async {
    final l10n = AppLocalizations.of(context);
    final body = app.stacksAuthMode == StacksAuthMode.off
        ? l10n.dialogResetBody
        : l10n.dialogResetBodyWithLock;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: cs.surface,
          elevation: 24,
          shadowColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.dialogResetTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      AppHaptics.light();
                      Navigator.of(ctx).pop(true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.outlineVariant,
                      foregroundColor: cs.onSurface,
                      textStyle: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    ),
                    child: Text(l10n.dialogResetConfirm),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      AppHaptics.light();
                      Navigator.of(ctx).pop(false);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.outlineVariant,
                      foregroundColor: cs.onSurface,
                      textStyle: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    ),
                    child: Text(l10n.buttonCancel),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true) app.resetSettings();
  }
}

// Render each option's label in its own language so a user stuck in the
// wrong UI language can still find their way out. Only the "System default"
// row follows the active UI language.
String _languageOptionLabel(BuildContext context, LanguagePref pref) {
  switch (pref) {
    case LanguagePref.system:
      return AppLocalizations.of(context).languageOptionSystem;
    case LanguagePref.enGB:
      return 'English';
    case LanguagePref.esES:
      return 'Español';
    case LanguagePref.ptBR:
      return 'Português';
    case LanguagePref.ruRU:
      return 'Русский';
    case LanguagePref.trTR:
      return 'Türkçe';
    case LanguagePref.viVN:
      return 'Tiếng Việt';
    case LanguagePref.jaJP:
      return '日本語';
    case LanguagePref.frFR:
      return 'Français';
    case LanguagePref.deDE:
      return 'Deutsch';
    case LanguagePref.itIT:
      return 'Italiano';
  }
}

// System default pinned at top; the rest sorted by the label shown to the
// user (in the language's own script). Sort is codepoint-based, so Latin
// labels come first (A–Z), then Cyrillic, then CJK — matches what iOS and
// Android language pickers do.
List<LanguagePref> _sortedLanguageOptions(BuildContext context) {
  final rest = LanguagePref.values
      .where((l) => l != LanguagePref.system)
      .toList()
    ..sort((a, b) => _languageOptionLabel(context, a)
        .compareTo(_languageOptionLabel(context, b)));
  return [LanguagePref.system, ...rest];
}

Future<LanguagePref?> _showLanguagePicker(
  BuildContext context,
  LanguagePref current,
) {
  return showDialog<LanguagePref>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (ctx) => RadioGroup<LanguagePref>(
      groupValue: current,
      onChanged: (v) {
        AppHaptics.selection();
        Navigator.of(ctx).pop(v);
      },
      child: SimpleDialog(
        elevation: 24,
        shadowColor: Colors.black,
        title: Text(AppLocalizations.of(ctx).languagePickerTitle),
        children: [
          for (final l in _sortedLanguageOptions(ctx))
            RadioListTile<LanguagePref>(
              key: ValueKey('language-${l.code}'),
              title: Text(_languageOptionLabel(ctx, l)),
              value: l,
            ),
        ],
      ),
    ),
  );
}
