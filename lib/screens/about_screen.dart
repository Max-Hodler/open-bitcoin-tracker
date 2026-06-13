import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_enums.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../state/state.dart';
import '../theme/theme.dart';
import '../widgets/scroll_hairline.dart';
import 'settings/settings_widgets.dart';

const String _kWebsiteUrl = 'https://openbitcointracker.com';
const String _kPrivacyPolicyUrl = 'https://openbitcointracker.com/privacy/';
const String _kSourceCodeUrl = 'https://github.com/Max-Hodler/open-bitcoin-tracker';
const String _kKrakenUrl = 'https://www.kraken.com';
const String _kCoinMetricsUrl = 'https://coinmetrics.io';
const String _kEcbUrl =
    'https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // App version, read from the bundle so the About screen always matches
  // pubspec.yaml. Empty until the async load completes (resolves near-
  // instantly), so the version line just renders blank for one frame.
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  Future<void> _confirmReset(BuildContext context) async {
    final app = context.read<AppStateNotifier>();
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
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
    if (confirmed == true && context.mounted) {
      context.read<AppStateNotifier>().resetSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
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
          l10n.settingsAbout,
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
            0,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                l10n.aboutAppName,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _SectionHeader(label: l10n.aboutSectionLinks),
            SettingsGroup(
              children: [
                _externalLinkTile(
                  context,
                  label: l10n.aboutWebsite,
                  value: 'openbitcointracker.com',
                  url: _kWebsiteUrl,
                ),
                _externalLinkTile(
                  context,
                  label: l10n.aboutSourceCode,
                  value: 'github.com',
                  url: _kSourceCodeUrl,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader(
              label: l10n.aboutSectionDataSources,
              bottomSpacing: AppSpacing.xs,
            ),
            _SectionNote(text: l10n.aboutDataSourceDisclaimer),
            SettingsGroup(
              children: [
                _externalLinkTile(
                  context,
                  label: l10n.aboutDataSourceLive,
                  value: 'Kraken',
                  url: _kKrakenUrl,
                ),
                _externalLinkTile(
                  context,
                  label: l10n.aboutDataSourceHistory,
                  value: 'Coin Metrics',
                  url: _kCoinMetricsUrl,
                ),
                _externalLinkTile(
                  context,
                  label: l10n.aboutDataSourceFx,
                  value: 'European Central Bank',
                  url: _kEcbUrl,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              children: [
                _externalLinkTile(
                  context,
                  label: l10n.aboutPrivacyPolicy,
                  value: '',
                  url: _kPrivacyPolicyUrl,
                ),
                SettingsPickerTile(
                  label: l10n.aboutLicenses,
                  value: '',
                  trailingIcon: Icons.chevron_right,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: l10n.aboutAppName,
                    applicationVersion: _appVersion,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              children: [
                SettingsActionTile(
                  label: l10n.settingsResetAllOptions,
                  onTap: () => _confirmReset(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _Footer(
              version: l10n.aboutVersion(_appVersion),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _externalLinkTile(
  BuildContext context, {
  required String label,
  required String value,
  required String url,
}) {
  return SettingsPickerTile(
    label: label,
    value: value,
    trailingIcon: Icons.open_in_new,
    onTap: () async {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    },
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.bottomSpacing = AppSpacing.sm});

  final String label;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: bottomSpacing),
      child: Text(
        label,
        style: AppTypography.body.copyWith(
          fontSize: 16,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SectionNote extends StatelessWidget {
  const _SectionNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppTypography.body.copyWith(
          fontSize: 13,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      version,
      textAlign: TextAlign.center,
      style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
    );
  }
}

