import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../about_screen.dart';
import '../../settings/settings_dialogs.dart';
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

class AddStackIconButton extends StatefulWidget {
  const AddStackIconButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<AddStackIconButton> createState() => _AddStackIconButtonState();
}

class _AddStackIconButtonState extends State<AddStackIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  bool _attention = false;

  @override
  void initState() {
    super.initState();
    // Construct eagerly in initState, not as a `late` initializer. The field
    // is only read when attention toggles on; a user who already has stacks
    // never trips that path, leaving a `late final` uninitialised until
    // dispose() touches it — building a Ticker against a deactivated element
    // and throwing. Eager construction keeps it inside a valid lifecycle.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  void _syncAttention(bool attention) {
    if (attention == _attention) return;
    _attention = attention;
    if (attention) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    // Pulse only for a user who has never added a stack — the waves teach them
    // where to start. Once they've added one (even if they later delete all),
    // the button is just a plain icon; they already know how.
    final attention = context.select<AppStateNotifier, bool>(
        (a) => a.stacks.isEmpty && !a.hasEverAddedStack);
    _syncAttention(attention);

    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (attention)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  size: const Size(36, 36),
                  painter: _AttentionWavePainter(
                    progress: _pulse.value,
                    color: p.bitcoinOrange,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: () {
              AppHaptics.light();
              widget.onTap();
            },
            icon: const Icon(Icons.add),
            iconSize: 22,
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              backgroundColor: cs.surface,
              foregroundColor: cs.onSurfaceVariant,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              elevation: 1.5,
              fixedSize: const Size(36, 36),
              minimumSize: const Size(36, 36),
              maximumSize: const Size(36, 36),
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two staggered expanding rings that fade as they grow, radiating from the
/// centre of the add button to draw the eye when no stacks exist yet.
class _AttentionWavePainter extends CustomPainter {
  const _AttentionWavePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const minRadius = 18.0;
    const maxRadius = 32.0;

    for (var i = 0; i < 2; i++) {
      // Stagger the second ring half a cycle behind the first.
      final t = (progress + i * 0.5) % 1.0;
      final radius = minRadius + (maxRadius - minRadius) * t;
      // Fade in over the first fifth of the cycle so rings emerge from the
      // centre instead of popping into existence, hold at full orange, then
      // fade out over the final stretch as they reach the edge.
      final fadeIn = (t / 0.2).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - t) / 0.4).clamp(0.0, 1.0);
      final opacity = fadeIn * fadeOut;
      if (opacity <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AttentionWavePainter old) =>
      old.progress != progress || old.color != color;
}

enum _OverflowAction { converter, language, currency, bitcoinUnit, theme, stacks, about, screenshot }

class OverflowButton extends StatefulWidget {
  const OverflowButton({super.key, this.onOpenConverter});

  final VoidCallback? onOpenConverter;

  @override
  State<OverflowButton> createState() => _OverflowButtonState();
}

class _OverflowButtonState extends State<OverflowButton> {
  final _menuKey = GlobalKey<PopupMenuButtonState<_OverflowAction>>();

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
      key: _menuKey,
      onOpened: AppHaptics.light,
      onSelected: (action) => _handleAction(context, action),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48),
      popUpAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 120)),
      offset: const Offset(0, 56),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: IconButton(
        onPressed: () {
          _menuKey.currentState?.showButtonMenu();
        },
        icon: const Icon(Icons.more_vert),
        iconSize: 22,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurfaceVariant,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          elevation: 1.5,
          fixedSize: const Size(36, 36),
          minimumSize: const Size(36, 36),
          maximumSize: const Size(36, 36),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: _OverflowAction.converter,
          child: IgnorePointer(child: Row(children: [
            Icon(Icons.swap_vert, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.homeConverter, style: itemStyle),
          ])),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _OverflowAction.language,
          child: IgnorePointer(child: Row(children: [
            Icon(Icons.language, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsLanguageLabel, style: itemStyle),
          ])),
        ),
        PopupMenuItem(
          value: _OverflowAction.currency,
          child: IgnorePointer(child: Row(children: [
            Icon(Icons.currency_exchange, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsCurrencies, style: itemStyle),
          ])),
        ),
        PopupMenuItem(
          value: _OverflowAction.bitcoinUnit,
          child: IgnorePointer(child: Row(children: [
            Icon(Icons.currency_bitcoin, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsBitcoinDisplayMode, style: itemStyle),
          ])),
        ),
        PopupMenuItem(
          value: _OverflowAction.stacks,
          child: IgnorePointer(child: Row(children: [
            Icon(Icons.reorder, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsGroupPrivacy, style: itemStyle),
          ])),
        ),
        PopupMenuItem(
          value: _OverflowAction.theme,
          child: IgnorePointer(child: Row(children: [
            Icon(Icons.palette_outlined, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsThemeLabel, style: itemStyle),
          ])),
        ),
        PopupMenuItem(
          value: _OverflowAction.about,
          child: IgnorePointer(child: Row(children: [
            Icon(Icons.info_outline, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(l10n.settingsAbout, style: itemStyle),
          ])),
        ),
        // Debug-only screenshot mode. Gated to debug builds — the tree-shaker
        // drops this branch from release/profile binaries, so it never ships.
        // Freezes the live price (hiding the delta badge) and swaps in the demo
        // portfolio for clean marketing screenshots.
        if (kDebugMode)
          PopupMenuItem(
            value: _OverflowAction.screenshot,
            child: IgnorePointer(child: Row(children: [
              Icon(
                context.read<LivePriceController>().screenshotMode
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text('Screenshot mode', style: itemStyle),
            ])),
          ),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context, _OverflowAction action) async {
    switch (action) {
      case _OverflowAction.converter:
        widget.onOpenConverter?.call();
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
      case _OverflowAction.bitcoinUnit:
        final app = context.read<AppStateNotifier>();
        final picked = await showBitcoinUnitDialog(context, app.btcDisplayMode);
        if (picked != null && context.mounted) {
          context.read<AppStateNotifier>().setBitcoinDisplayMode(picked);
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
      case _OverflowAction.screenshot:
        // Drive both controllers in lockstep: the live price freezes at the
        // fixed figure and the stack list swaps to the demo set, so the whole
        // home screen is camera-ready in one tap.
        final live = context.read<LivePriceController>();
        final next = !live.screenshotMode;
        live.screenshotMode = next;
        context.read<AppStateNotifier>().screenshotMode = next;
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

