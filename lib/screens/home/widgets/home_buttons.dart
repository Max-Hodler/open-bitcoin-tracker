import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../about_screen.dart';
import '../../settings/settings_screen.dart';

class HomeButton extends StatelessWidget {
  const HomeButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.height = 52,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: InkWell(
          onTap: onTap == null ? null : () {
            AppHaptics.light();
            onTap!();
          },
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontSize: 16,
                      color: cs.onSurface.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid bitcoin-orange FAB used for primary home-screen actions.
class HomeFab extends StatelessWidget {
  const HomeFab({super.key, required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FloatingActionButton(
      onPressed: () {
        AppHaptics.medium();
        onTap?.call();
      },
      backgroundColor: p.bitcoinOrange,
      foregroundColor: Colors.white,
      tooltip: tooltip,
      child: Icon(icon, size: 24),
    );
  }
}


class ConverterIconButton extends StatelessWidget {
  const ConverterIconButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 47,
          child: Transform.flip(
            flipX: true,
            child: Icon(
              Icons.swap_vert,
              size: 26,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class AddStackIconButton extends StatelessWidget {
  const AddStackIconButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 47,
          child: Icon(
            Icons.add,
            size: 26,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

enum _OverflowAction { converter, language, currency, theme, stacks, about }

class OverflowButton extends StatelessWidget {
  const OverflowButton({super.key, this.onOpenConverter});

  final VoidCallback? onOpenConverter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final itemStyle = AppTypography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: cs.onSurface,
    );
    return PopupMenuButton<_OverflowAction>(
      onOpened: AppHaptics.light,
      onSelected: (action) => _handleAction(context, action),
      icon: Icon(Icons.more_vert, size: 24, color: cs.onSurfaceVariant),
      iconSize: 24,
      constraints: const BoxConstraints(minWidth: 48),
      popUpAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 120)),
      offset: const Offset(0, 56),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: _OverflowAction.converter,
          child: Row(children: [
            Icon(Icons.swap_vert, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.homeConverter, style: itemStyle),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _OverflowAction.language,
          child: Row(children: [
            Icon(Icons.language, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsLanguageLabel, style: itemStyle),
          ]),
        ),
        PopupMenuItem(
          value: _OverflowAction.currency,
          child: Row(children: [
            Icon(Icons.currency_exchange, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsCurrencies, style: itemStyle),
          ]),
        ),
        PopupMenuItem(
          value: _OverflowAction.theme,
          child: Row(children: [
            Icon(Icons.palette_outlined, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsThemeLabel, style: itemStyle),
          ]),
        ),
        PopupMenuItem(
          value: _OverflowAction.stacks,
          child: Row(children: [
            Icon(Icons.reorder, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsGroupPrivacy, style: itemStyle),
          ]),
        ),
        PopupMenuItem(
          value: _OverflowAction.about,
          child: Row(children: [
            Icon(Icons.info_outline, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsAbout, style: itemStyle),
          ]),
        ),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context, _OverflowAction action) async {
    switch (action) {
      case _OverflowAction.converter:
        onOpenConverter?.call();
      case _OverflowAction.language:
        final app = context.read<AppStateNotifier>();
        final picked = await _showLanguagePicker(context, app.language);
        if (picked != null && context.mounted) app.setLanguage(picked);
      case _OverflowAction.currency:
        final app = context.read<AppStateNotifier>();
        final picked = await Navigator.of(context).push<List<Currency>>(
          MaterialPageRoute(
            builder: (_) => CurrencyPickerScreen(initial: app.selectedCurrencies),
          ),
        );
        if (picked != null && context.mounted) {
          context.read<AppStateNotifier>().setSelectedCurrencies(picked);
        }
      case _OverflowAction.theme:
        if (context.mounted) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const ThemeSettingsScreen()),
          );
        }
      case _OverflowAction.stacks:
        if (context.mounted) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const StacksSettingsScreen()),
          );
        }
      case _OverflowAction.about:
        if (context.mounted) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
          );
        }
    }
  }
}

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

