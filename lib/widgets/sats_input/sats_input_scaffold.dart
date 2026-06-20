import 'package:flutter/material.dart';

import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../theme/theme.dart';
import '../number_pad.dart';
import 'sats_fiat_label.dart';
import 'sats_input_display.dart';

/// Full screen layout for the amount-entry flow: app bar, the [SatsInputDisplay]
/// + [SatsFiatLabel] header, a reserved leading-zero warning row, and the
/// [NumberPad] keypad at the bottom. Used by both the new-stack and
/// edit-stack amount screens, with the calling screen owning the input state.
class SatsInputScaffold extends StatelessWidget {
  const SatsInputScaffold({
    super.key,
    required this.input,
    required this.caret,
    required this.isValid,
    required this.mode,
    required this.onInput,
    required this.onDelete,
    required this.onClear,
    required this.onConfirm,
    required this.zeroDisabled,
    required this.onZeroBlocked,
    required this.showLeadingZeroWarning,
    this.confirmLabel,
    this.onInputLongPressAt,
    this.onCaretAt,
    this.header,
    this.subHeader,
    this.warning,
    this.title,
    this.showUnitHint = true,
  });

  final String input;
  final int caret;
  final bool isValid;
  final BtcDisplayMode mode;
  final void Function(String) onInput;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback onConfirm;
  final bool zeroDisabled;
  final VoidCallback onZeroBlocked;
  final bool showLeadingZeroWarning;
  final String? confirmLabel;
  final ValueChanged<Offset>? onInputLongPressAt;
  final ValueChanged<int>? onCaretAt;

  /// Optional widget rendered between the app bar and the amount display —
  /// used by the edit-amount screen for the Set/Add/Subtract toggle. Null on
  /// the new-stack flow.
  final Widget? header;

  /// Optional widget rendered just below the amount display + fiat label —
  /// used by the edit-amount screen for the current/new balance readout. Null
  /// on the new-stack flow.
  final Widget? subHeader;

  /// Optional override for the warning row above the keypad. When non-null it
  /// replaces the leading-zero warning text (e.g. the subtract-underflow
  /// message); the row stays reserved either way so the layout never jumps.
  final String? warning;

  /// Optional app-bar title override. Defaults to the generic "Bitcoin amount"
  /// label used by the new-stack flow.
  final String? title;

  /// Forwarded to [SatsFiatLabel]: when false, suppresses the empty-input unit
  /// hint. The edit-amount screen sets this false.
  final bool showUnitHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final hPad = isLandscape ? 64.0 : AppSpacing.md;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56 + (hPad - AppSpacing.md),
        leading: Padding(
          padding: EdgeInsets.only(left: hPad - AppSpacing.md),
          child: BackButton(
            color: cs.onSurfaceVariant,
            onPressed: () {
              AppHaptics.light();
              Navigator.of(context).maybePop();
            },
          ),
        ),
        centerTitle: true,
        titleSpacing: hPad,
        title: Text(
          title ?? l10n.satsInputLabel,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            hPad,
            header != null ? AppSpacing.sm : AppSpacing.md,
            hPad,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[
                header!,
                const SizedBox(height: AppSpacing.lg),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SatsInputDisplay(
                      input: input,
                      caret: caret,
                      mode: mode,
                      onLongPressAt: onInputLongPressAt,
                      onCaretAt: onCaretAt,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SatsFiatLabel(
                      input: input,
                      mode: mode,
                      showUnitHint: showUnitHint,
                    ),
                    if (subHeader != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      subHeader!,
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Opacity(
                  opacity:
                      (warning != null || showLeadingZeroWarning) ? 1.0 : 0.0,
                  child: Text(
                    warning ?? l10n.satsInputLeadingZeroWarning,
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      fontSize: 14,
                      letterSpacing: 1.2,
                      color: cs.error,
                    ),
                  ),
                ),
              ),
              NumberPad(
                onInput: onInput,
                onDelete: onDelete,
                onClear: onClear,
                onEnter: onConfirm,
                isValid: isValid,
                isEmpty: input.isEmpty,
                // Decimal key + locale separator only in BTC mode. In sats
                // mode the leading-zero gate uses [zeroDisabled] as before.
                showDecimal: mode == BtcDisplayMode.btc,
                decimalLabel: localeDecimalSeparator,
                zeroDisabled: zeroDisabled,
                onZeroBlocked: onZeroBlocked,
                confirmLabel: confirmLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
