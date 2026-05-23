import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_enums.dart';
import '../data/data.dart' as model;
import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../state/state.dart';
import '../theme/theme.dart';
import '../widgets/sats_input/sats_input.dart';
import '../widgets/stack_name/stack_name.dart';

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
    final sats = mode == BtcDisplayMode.btc
        ? model.Sats.btcRawToSats(_input)
        : (int.tryParse(_input) ?? 0);
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
    return SatsInputScaffold(
      input: _input,
      caret: _caret,
      isValid: _input.isNotEmpty && _input != '0' && _input != '0.',
      mode: mode,
      onInput: (ch) => _onInput(ch, mode),
      onDelete: _onDelete,
      onClear: _onClear,
      onConfirm: () => _onConfirm(mode),
      zeroDisabled: mode == BtcDisplayMode.sats && _input.isEmpty,
      onZeroBlocked: _onZeroBlocked,
      showLeadingZeroWarning: _showLeadingZeroWarning,
      confirmLabel: AppLocalizations.of(context).stackMenuUpdateAmount,
      onInputLongPressAt: (pos) => _onLongPressAt(pos, mode),
      onCaretAt: _onCaretAt,
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
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StackNameField(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.sm),
              StackNameLimitLabel(visible: _atLimit),
              const SizedBox(height: AppSpacing.lg),
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
