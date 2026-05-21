import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../widgets/scroll_hairline.dart';
import 'settings/_widgets.dart';

const String _kAppVersion = '1.0';
const String _kGitHubUrl = 'https://github.com/Max-Hodler/open-bitcoin-tracker';
const String _kPrivacyPolicyUrl =
    'https://max-hodler.github.io/open-bitcoin-tracker/privacy/';
const String _kKrakenUrl = 'https://www.kraken.com';
const String _kCoinMetricsUrl = 'https://coinmetrics.io';
const String _kEcbUrl =
    'https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html';
const String _kMempoolSpaceUrl = 'https://mempool.space';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
          l10n.aboutAppName,
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
            AppSpacing.xl,
          ),
          children: [
            _SectionHeader(label: l10n.aboutSectionLinks),
            SettingsGroup(
              children: [
                _externalLinkTile(
                  context,
                  label: l10n.aboutGitHub,
                  value: 'GitHub',
                  url: _kGitHubUrl,
                ),
                _externalLinkTile(
                  context,
                  label: l10n.aboutPrivacyPolicy,
                  value: '',
                  url: _kPrivacyPolicyUrl,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader(label: l10n.aboutSectionDataSources),
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
                _externalLinkTile(
                  context,
                  label: l10n.aboutDataSourceMempool,
                  value: 'mempool.space',
                  url: _kMempoolSpaceUrl,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              children: [
                SettingsPickerTile(
                  label: l10n.aboutLicenses,
                  value: '',
                  trailingIcon: Icons.chevron_right,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: l10n.aboutAppName,
                    applicationVersion: _kAppVersion,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _Footer(
              version: l10n.aboutVersion(_kAppVersion),
              madeBy: l10n.aboutMadeBy,
              dedication: l10n.aboutDedication,
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
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.version,
    required this.madeBy,
    required this.dedication,
  });

  final String version;
  final String madeBy;
  final String dedication;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          version,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          madeBy,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          dedication,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

