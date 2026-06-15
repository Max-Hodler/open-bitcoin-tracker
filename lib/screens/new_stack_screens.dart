import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_enums.dart';
import '../data/data.dart' as model;
import '../l10n/generated/app_localizations.dart';
import '../state/state.dart';
import '../widgets/sats_input/sats_input.dart';
import 'stack_name_screen_mixin.dart';

class NewStackAmountScreen extends StatefulWidget {
  const NewStackAmountScreen({super.key, this.initialSats});

  final int? initialSats;

  @override
  State<NewStackAmountScreen> createState() => _NewStackAmountScreenState();
}

class _NewStackAmountScreenState extends State<NewStackAmountScreen> {
  late String _input;
  late int _caret;
  bool _showLeadingZeroWarning = false;
  // Tracks the [BtcDisplayMode] the in-progress [_input] is interpreted in.
  // When the user flips it in Settings mid-edit, we re-derive [_input] in
  // build (post-frame) so the visible value matches the new unit.
  BtcDisplayMode? _modeAtInit;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSats;
    final mode = context.read<AppStateNotifier>().btcDisplayMode;
    _modeAtInit = mode;
    _input = _initialInputFor(initial, mode);
    _caret = _input.length;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-interpret [_input] when the user flips the display mode mid-edit.
    // build()'s select on btcDisplayMode makes a mode change re-trigger
    // this hook; _maybeMigrateForMode is a no-op when the mode is unchanged.
    _maybeMigrateForMode(context.read<AppStateNotifier>().btcDisplayMode);
  }

  static String _initialInputFor(int? initialSats, BtcDisplayMode mode) {
    if (initialSats == null || initialSats == 0) return '';
    return mode == BtcDisplayMode.btc
        ? model.Sats.satsToBtcRaw(initialSats)
        : initialSats.toString();
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
    // sats mode (original behavior).
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

  int _enteredSats(BtcDisplayMode mode) => mode == BtcDisplayMode.btc
      ? model.Sats.btcRawToSats(_input)
      : (int.tryParse(_input) ?? 0);

  void _onConfirm(BtcDisplayMode mode) {
    final sats = _enteredSats(mode);
    if (sats == 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewStackNameScreen(sats: sats),
      ),
    );
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
      (a) => a.btcDisplayMode,
    );
    return SatsInputScaffold(
      input: _input,
      caret: _caret,
      isValid: _input.isNotEmpty && _enteredSats(mode) > 0,
      mode: mode,
      onInput: (ch) => _onInput(ch, mode),
      onDelete: _onDelete,
      onClear: _onClear,
      onConfirm: () => _onConfirm(mode),
      // Leading-zero gate is sats-mode-only; BTC mode allows "0." starts.
      zeroDisabled: mode == BtcDisplayMode.sats && _input.isEmpty,
      onZeroBlocked: _onZeroBlocked,
      showLeadingZeroWarning: _showLeadingZeroWarning,
      title: AppLocalizations.of(context).newStackTitle,
      confirmLabel: AppLocalizations.of(context).buttonNext,
      onInputLongPressAt: (pos) => _onLongPressAt(pos, mode),
      onCaretAt: _onCaretAt,
    );
  }
}

class NewStackNameScreen extends StatefulWidget {
  const NewStackNameScreen({super.key, required this.sats});

  final int sats;

  @override
  State<NewStackNameScreen> createState() => _NewStackNameScreenState();
}

class _NewStackNameScreenState extends State<NewStackNameScreen>
    with StackNameScreenMixin {
  void _submit() {
    if (!isValid) return;
    context.read<AppStateNotifier>().addStack(model.Stack(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: trimmed,
          sats: widget.sats,
        ));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return buildNameScaffold(
      context: context,
      cs: cs,
      title: l10n.newStackTitle,
      confirmLabel: l10n.homeAddStack,
      onSubmit: _submit,
    );
  }
}
