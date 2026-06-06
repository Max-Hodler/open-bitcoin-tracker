import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_enums.dart';
import '../data/data.dart' as model;
import '../data/fiat.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../state/state.dart';
import '../theme/theme.dart';
import '../widgets/sats_input/sats_input.dart';
import '../widgets/stack_name/stack_name.dart';

/// How the amount entered on [EditStackAmountScreen] is applied to the stack's
/// current balance. [set] replaces it (the original behavior); [add] and
/// [subtract] treat the entry as a delta so users can record a buy or sell
/// without computing the new total themselves.
enum EditAmountMode { set, add, subtract }

class EditStackAmountScreen extends StatefulWidget {
  const EditStackAmountScreen({super.key, required this.stackId});

  final String stackId;

  @override
  State<EditStackAmountScreen> createState() => _EditStackAmountScreenState();
}

class _EditStackAmountScreenState extends State<EditStackAmountScreen> {
  late String _input;
  late int _caret;
  bool _showLeadingZeroWarning = false;
  EditAmountMode _mode = EditAmountMode.set;
  late final model.Stack _original;
  late final StacksLockController _lock;
  // See [NewStackAmountScreen]: tracks the [BtcDisplayMode] [_input] is
  // currently interpreted in so a mid-edit flip re-derives the visible value.
  BtcDisplayMode? _modeAtInit;

  @override
  void initState() {
    super.initState();
    _original = context.read<AppStateNotifier>().stacks.firstWhere(
          (s) => s.id == widget.stackId,
          orElse: () => throw StateError('Stack ${widget.stackId} not found'),
        );
    final mode = context.read<AppStateNotifier>().bitcoinDisplayMode;
    _modeAtInit = mode;
    _input = _original.sats == 0
        ? ''
        : (mode == BtcDisplayMode.btc
            ? model.Sats.satsToBtcRaw(_original.sats)
            : _original.sats.toString());
    _caret = _input.length;
    // If the stacks re-lock while the user is on this screen (e.g. they
    // backgrounded the app and the timeout fired on resume), the underlying
    // stack data is gone — pop back to home so they can re-authenticate
    // before retrying their edit.
    _lock = context.read<StacksLockController>();
    _lock.addListener(_popIfLocked);
  }

  @override
  void dispose() {
    _lock.removeListener(_popIfLocked);
    super.dispose();
  }

  void _popIfLocked() {
    if (!mounted || !_lock.isLocked) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _maybeMigrateForMode(BtcDisplayMode mode) {
    if (_modeAtInit == mode) return;
    final prev = _modeAtInit;
    _modeAtInit = mode;
    if (prev == null || _input.isEmpty) return;
    final sats = prev == BtcDisplayMode.btc
        ? model.Sats.btcRawToSats(_input)
        : (int.tryParse(_input) ?? 0);
    setState(() {
      _input = mode == BtcDisplayMode.btc
          ? model.Sats.satsToBtcRaw(sats)
          : (sats == 0 ? '' : sats.toString());
      _caret = _input.length;
      _showLeadingZeroWarning = false;
    });
  }

  /// The amount currently typed, in sats, for the active [mode].
  int _enteredSats(BtcDisplayMode mode) => mode == BtcDisplayMode.btc
      ? model.Sats.btcRawToSats(_input)
      : (int.tryParse(_input) ?? 0);

  /// The balance the stack would have if confirmed now. May be negative for a
  /// subtract that overshoots — callers gate on that before saving.
  int _resultSats(BtcDisplayMode mode) {
    final entered = _enteredSats(mode);
    return switch (_mode) {
      EditAmountMode.set => entered,
      EditAmountMode.add => _original.sats + entered,
      EditAmountMode.subtract => _original.sats - entered,
    };
  }

  bool _isUnderflow(BtcDisplayMode mode) =>
      _mode == EditAmountMode.subtract &&
      _input.isNotEmpty &&
      _resultSats(mode) < 0;

  void _onModeChanged(EditAmountMode next, BtcDisplayMode displayMode) {
    if (next == _mode) return;
    setState(() {
      _mode = next;
      // Switching between an absolute total and a delta makes the pre-filled
      // value meaningless, so start the new entry empty for add/subtract. When
      // returning to Set, restore the stack's current total as the baseline.
      if (next == EditAmountMode.set) {
        _input = _original.sats == 0
            ? ''
            : (displayMode == BtcDisplayMode.btc
                ? model.Sats.satsToBtcRaw(_original.sats)
                : _original.sats.toString());
      } else {
        _input = '';
      }
      _caret = _input.length;
      _showLeadingZeroWarning = false;
    });
  }

  void _onInput(String ch, BtcDisplayMode mode) {
    if (mode == BtcDisplayMode.btc) {
      final result = model.Sats.tryInsertBtcChar(_input, _caret, ch);
      if (result == null) return;
      setState(() {
        _input = result.$1;
        _caret = result.$2;
        _showLeadingZeroWarning = false;
      });
      return;
    }
    if (_input.length >= model.Sats.maxInputDigits) return;
    if (ch == '0' && _caret == 0 && _input.isNotEmpty) {
      _onZeroBlocked();
      return;
    }
    final next = _input.substring(0, _caret) + ch + _input.substring(_caret);
    final parsed = BigInt.tryParse(next);
    if (parsed == null) return;
    if (parsed > BigInt.from(model.Sats.maxSupply)) return;
    setState(() {
      _input = next;
      _caret += 1;
      _showLeadingZeroWarning = false;
    });
  }

  void _onZeroBlocked() {
    setState(() => _showLeadingZeroWarning = true);
  }

  void _onDelete() {
    if (_input.isEmpty || _caret == 0) return;
    setState(() {
      _input = _input.substring(0, _caret - 1) + _input.substring(_caret);
      _caret -= 1;
    });
  }

  void _onClear() {
    if (_input.isEmpty) return;
    setState(() {
      _input = '';
      _caret = 0;
      _showLeadingZeroWarning = false;
    });
  }

  void _onConfirm(BtcDisplayMode mode) {
    // Block & warn: a subtract that would drive the balance negative is
    // rejected rather than clamped, so the user fixes the amount explicitly.
    if (_isUnderflow(mode)) return;
    final sats = _resultSats(mode);
    context.read<AppStateNotifier>().updateStack(
          widget.stackId,
          (s) => s.copyWith(sats: sats),
        );
    Navigator.of(context).pop();
  }

  void _onCaretAt(int index) {
    if (index < 0 || index > _input.length) return;
    if (_caret == index) return;
    setState(() => _caret = index);
  }

  void _onLongPressAt(Offset globalPos, BtcDisplayMode mode) {
    showSatsInputMenu(
      context: context,
      globalPos: globalPos,
      currentInput: _input,
      mode: mode,
      onPasteAccepted: (value) {
        setState(() {
          _input = value;
          _caret = value.length;
          _showLeadingZeroWarning = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppStateNotifier, BtcDisplayMode>(
      (a) => a.bitcoinDisplayMode,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeMigrateForMode(mode);
    });
    final l10n = AppLocalizations.of(context);
    final underflow = _isUnderflow(mode);
    final confirmLabel = switch (_mode) {
      EditAmountMode.set => l10n.stackMenuUpdateAmount,
      EditAmountMode.add => l10n.editAmountConfirmAdd,
      EditAmountMode.subtract => l10n.editAmountConfirmSubtract,
    };
    return SatsInputScaffold(
      title: l10n.stackMenuUpdateAmount,
      showUnitHint: false,
      input: _input,
      caret: _caret,
      isValid:
          _input.isNotEmpty && _input != '0' && _input != '0.' && !underflow,
      mode: mode,
      onInput: (ch) => _onInput(ch, mode),
      onDelete: _onDelete,
      onClear: _onClear,
      onConfirm: () => _onConfirm(mode),
      zeroDisabled: mode == BtcDisplayMode.sats && _input.isEmpty,
      onZeroBlocked: _onZeroBlocked,
      showLeadingZeroWarning: _showLeadingZeroWarning,
      confirmLabel: confirmLabel,
      onInputLongPressAt: (pos) => _onLongPressAt(pos, mode),
      onCaretAt: _onCaretAt,
      warning: underflow ? l10n.editAmountSubtractUnderflow : null,
      header: _EditAmountTabs(
        mode: _mode,
        onModeChanged: (m) => _onModeChanged(m, mode),
      ),
      subHeader: _EditAmountBalanceLine(
        mode: _mode,
        currentSats: _original.sats,
        // Preview the resulting balance only for deltas with a value typed;
        // for Set the input itself already shows the new total.
        resultSats: (_mode != EditAmountMode.set && _input.isNotEmpty)
            ? _resultSats(mode)
            : null,
        displayMode: mode,
      ),
    );
  }
}

/// The Set/Add/Subtract selector for [EditStackAmountScreen], rendered above
/// the amount display.
class _EditAmountTabs extends StatelessWidget {
  const _EditAmountTabs({required this.mode, required this.onModeChanged});

  final EditAmountMode mode;
  final ValueChanged<EditAmountMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final segments = <(EditAmountMode, String)>[
      (EditAmountMode.subtract, l10n.editAmountModeSubtract),
      (EditAmountMode.set, l10n.editAmountModeSet),
      (EditAmountMode.add, l10n.editAmountModeAdd),
    ];
    return Row(
      children: [
        for (final (value, label) in segments)
          _SegmentButton(
            label: label,
            selected: value == mode,
            onTap: () => onModeChanged(value),
          ),
      ],
    );
  }
}

/// Current/new balance readout for [EditStackAmountScreen], rendered below the
/// amount display + fiat label. In Set mode no line is shown (the amount field
/// already holds the resulting total); for Add/Subtract it shows the current
/// balance, switching to the resulting-balance preview once a delta is typed.
class _EditAmountBalanceLine extends StatelessWidget {
  const _EditAmountBalanceLine({
    required this.mode,
    required this.currentSats,
    required this.resultSats,
    required this.displayMode,
  });

  final EditAmountMode mode;
  final int currentSats;
  final int? resultSats;
  final BtcDisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isPreview = resultSats != null;
    final label = mode == EditAmountMode.set
        ? null
        : isPreview
            ? l10n.editAmountResultingLabel
            : l10n.editAmountCurrentLabel;
    final amount = mode == EditAmountMode.set
        ? null
        : formatBtcAmount(isPreview ? resultSats! : currentSats,
            mode: displayMode);
    // Reserve the row height even in Set mode so the keypad below doesn't
    // shift when the user switches modes. The amount line matches the fiat
    // label's font size.
    return SizedBox(
      height: 44,
      child: label == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  amount!,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    fontSize: 18,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Underlined segment matching the converter screen's [_ModeToggle]: plain
/// label text with a bitcoin-orange underline under the active mode. The
/// selected segment is non-tappable.
class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selected
              ? null
              : () {
                  AppHaptics.light();
                  onTap();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 2,
                        color: selected
                            ? palette.bitcoinOrange
                            : Colors.transparent,
                      ),
                    ],
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

class EditStackNameScreen extends StatefulWidget {
  const EditStackNameScreen({super.key, required this.stackId});

  final String stackId;

  @override
  State<EditStackNameScreen> createState() => _EditStackNameScreenState();
}

class _EditStackNameScreenState extends State<EditStackNameScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final StacksLockController _lock;

  @override
  void initState() {
    super.initState();
    final existing = context.read<AppStateNotifier>().stacks.firstWhere(
          (s) => s.id == widget.stackId,
          orElse: () => throw StateError('Stack ${widget.stackId} not found'),
        );
    _controller = TextEditingController(text: existing.name)
      ..addListener(() => setState(() {}));
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    // See EditStackAmountScreen: bail to home if the stacks re-lock while
    // we're mid-edit (resume timeout fires, manual lock, etc.).
    _lock = context.read<StacksLockController>();
    _lock.addListener(_popIfLocked);
  }

  @override
  void dispose() {
    _lock.removeListener(_popIfLocked);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _popIfLocked() {
    if (!mounted || !_lock.isLocked) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  String get _trimmed => _controller.text.trim();
  bool get _isValid => _trimmed.isNotEmpty;
  bool get _atLimit => _controller.text.length >= model.Stack.maxNameLength;

  void _submit() {
    if (!_isValid) return;
    final name = _trimmed.isEmpty
        ? AppLocalizations.of(context).stackUnnamedFallback
        : _trimmed;
    context.read<AppStateNotifier>().updateStack(
          widget.stackId,
          (s) => s.copyWith(name: name),
        );
    Navigator.of(context).pop();
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
        leading: BackButton(
          color: cs.onSurfaceVariant,
          onPressed: () {
            AppHaptics.light();
            Navigator.of(context).maybePop();
          },
        ),
        centerTitle: true,
        title: Text(
          l10n.stackNameLabel,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StackNameField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    StackNameLimitLabel(visible: _atLimit),
                  ],
                ),
              ),
              StackNameConfirmButton(
                isValid: _isValid,
                onTap: _submit,
                label: l10n.stackMenuChangeName,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
