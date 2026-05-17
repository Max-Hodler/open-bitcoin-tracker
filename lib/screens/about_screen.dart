import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../theme/theme.dart';
import '../widgets/scroll_hairline.dart';

const String _kAppVersion = '1.0';
const String _kGitHubUrl = 'https://github.com/Max-Hodler/open-bitcoin-tracker';
const String _kPrivacyPolicyUrl =
    'https://max-hodler.github.io/open-bitcoin-tracker/privacy/';
const String _kKrakenUrl = 'https://www.kraken.com';
const String _kCoinMetricsUrl = 'https://coinmetrics.io';
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
          _Section(
            label: l10n.aboutSectionLinks,
            child: Column(
              spacing: AppSpacing.xs,
              children: [
                _ExternalLinkTile(
                  label: l10n.aboutGitHub,
                  subtitle: 'GitHub',
                  url: _kGitHubUrl,
                ),
                _ExternalLinkTile(
                  label: l10n.aboutPrivacyPolicy,
                  url: _kPrivacyPolicyUrl,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Section(
            label: l10n.aboutSectionDataSources,
            child: Column(
              spacing: AppSpacing.xs,
              children: [
                _ExternalLinkTile(
                  label: l10n.aboutDataSourceLive,
                  subtitle: 'Kraken',
                  url: _kKrakenUrl,
                ),
                _ExternalLinkTile(
                  label: l10n.aboutDataSourceHistory,
                  subtitle: 'Coin Metrics',
                  url: _kCoinMetricsUrl,
                ),
                _ExternalLinkTile(
                  label: l10n.aboutDataSourceMempool,
                  subtitle: 'mempool.space',
                  url: _kMempoolSpaceUrl,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: AppSpacing.lg),
          _LicensesTile(label: l10n.aboutLicenses),
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

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              fontSize: 16,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ExternalLinkTile extends StatelessWidget {
  const _ExternalLinkTile({
    required this.label,
    required this.url,
    this.subtitle,
  });

  final String label;
  final String url;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        onTap: () async {
          AppHaptics.selection();
          await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );
        },
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: subtitle != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: AppTypography.body.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: AppTypography.body.copyWith(
                              fontSize: 16,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        label,
                        style: AppTypography.body.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              Icon(
                Icons.open_in_new,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicensesTile extends StatelessWidget {
  const _LicensesTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          showLicensePage(
            context: context,
            applicationName: AppLocalizations.of(context).aboutAppName,
            applicationVersion: _kAppVersion,
          );
        },
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 24,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
