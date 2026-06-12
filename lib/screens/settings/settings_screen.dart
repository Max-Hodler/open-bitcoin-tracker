import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import '../about_screen.dart';
import 'settings_widgets.dart';
import 'btc_price_settings_screen.dart';
import 'graph_settings_screen.dart';
import 'stacks_settings_screen.dart';
import 'theme_settings_screen.dart';
import 'widgets_settings_screen.dart';

// Re-export the public sub-screen classes so external callers (main.dart,
// home_screen.dart, settings_screen_test.dart) can keep importing this single
// file without caring how the package is laid out internally.
export 'btc_price_settings_screen.dart' show BtcPriceSettingsScreen;
export 'graph_settings_screen.dart' show GraphSettingsScreen;
export 'currency_picker_screen.dart' show CurrencyPickerScreen;
export 'stacks_settings_screen.dart' show StacksSettingsScreen;
export 'theme_settings_screen.dart' show ThemeSettingsScreen;
export 'widgets_settings_screen.dart' show WidgetsSettingsScreen;

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
                  label: l10n.settingsPriceLabel,
                  value: '',
                  onTap: () => _openBtcPriceSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsPickerTile(
                  label: l10n.settingsGraphLabel,
                  value: '',
                  onTap: () => _openGraphSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsPickerTile(
                  label: l10n.settingsGroupPrivacy,
                  value: '',
                  onTap: () => _openStacksSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsPickerTile(
                  label: l10n.settingsWidgets,
                  value: '',
                  onTap: () => _openWidgetsSettings(context),
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
            // Debug-only screenshot mode. Gated to debug builds — the
            // tree-shaker drops this whole branch from release/profile binaries,
            // so it never ships. Freezes the live price (and thus hides the
            // delta badge) for clean marketing screenshots.
            if (kDebugMode) ...[
              const SizedBox(height: AppSpacing.md),
              SettingsGroup(
                children: [
                  Builder(
                    builder: (context) {
                      final live = context.watch<LivePriceController>();
                      return SettingsToggleTile(
                        label: 'Screenshot mode',
                        value: live.screenshotMode,
                        enabled: true,
                        // Drive both controllers in lockstep: the live price
                        // freezes at the fixed figure and the stack list swaps
                        // to the demo set, so the whole home screen is camera-
                        // ready in one tap.
                        onChanged: (v) {
                          live.screenshotMode = v;
                          context.read<AppStateNotifier>().screenshotMode = v;
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
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

  void _openGraphSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const GraphSettingsScreen()),
    );
  }

  void _openStacksSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const StacksSettingsScreen()),
    );
  }

  void _openWidgetsSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const WidgetsSettingsScreen(),
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
