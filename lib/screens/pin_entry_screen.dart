import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../services/stacks_auth_service.dart';
import '../services/stacks_crypto_service.dart';
import '../services/stacks_unlock_orchestrator.dart';
import '../state/stacks_lock_controller.dart';
import '../theme/theme.dart';
import '../widgets/cancel_bar.dart';
import '../widgets/number_pad.dart';

enum _PinFlow { verify, setup, change }

enum _SetupStep { enter, confirm }

const int _kPinLength = 4;

/// Sentinel returned via Navigator.pop when the stacks blob failed its MAC
/// check after a successful PIN unwrap — the data is corrupt and the caller
/// must escalate to a destructive reset. Distinct from `true` (normal
/// success) and `false`/`null` (cancel) so callers can switch on it.
const Object _kCorruptSentinel = _CorruptBlobSentinel();

class _CorruptBlobSentinel {
  const _CorruptBlobSentinel();
}

/// True if a Navigator.pop result from PinEntryScreen indicates corruption.
bool isPinCorruptResult(Object? result) => result is _CorruptBlobSentinel;

class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen.verify({super.key, this.title})
      : _flow = _PinFlow.verify,
        _collectOnly = false;

  /// First-time setup. The screen mints a DEK and migrates plaintext stacks
  /// to ciphertext on success. Use this for off → pin transitions.
  const PinEntryScreen.setup({super.key})
      : _flow = _PinFlow.setup,
        _collectOnly = false,
        title = null;

  /// Like [setup] but pops the entered PIN instead of running migration.
  /// Used by mode transitions where the DEK is already in memory and the
  /// caller will perform the rewrap itself.
  const PinEntryScreen.collect({super.key})
      : _flow = _PinFlow.setup,
        _collectOnly = true,
        title = null;

  const PinEntryScreen.change({super.key})
      : _flow = _PinFlow.change,
        _collectOnly = false,
        title = null;

  final _PinFlow _flow;
  final bool _collectOnly;
  final String? title;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen>
    with TickerProviderStateMixin {
  String _input = '';
  String? _firstPinDuringSetup;
  _SetupStep _setupStep = _SetupStep.enter;
  bool _changeVerified = false; // change-mode: true once current PIN was confirmed
  List<int>? _changeOldDek; // change-mode: held between verify and rewrap
  String _statusMessage = '';
  bool _statusIsError = false;
  Timer? _cooldownTimer;
  Duration _cooldownRemaining = Duration.zero;
  late final AnimationController _shakeCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    if (widget._flow != _PinFlow.setup) {
      // Resume an in-progress cooldown that was started in a previous screen
      // instance — possibly even a previous app process.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final remaining = await _service.getRemainingCooldown();
        if (!mounted || remaining == null) return;
        _startCooldown(remaining);
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  StacksAuthService get _service => context.read<StacksAuthService>();
  StacksCryptoService get _crypto => context.read<StacksCryptoService>();
  StacksUnlockOrchestrator get _orch =>
      context.read<StacksUnlockOrchestrator>();

  bool get _onCooldown => _cooldownRemaining > Duration.zero;
  bool get _isValid =>
      !_onCooldown && !_busy && _input.length == _kPinLength;

  void _setStatus(String message, {bool error = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = error;
    });
  }

  void _shakeAndClear() {
    _shakeCtrl.forward(from: 0);
    AppHaptics.heavy();
    setState(() => _input = '');
  }

  void _onInput(String digit) {
    if (!mounted || _onCooldown || _busy) return;
    if (_input.length >= _kPinLength) return;
    setState(() {
      _input += digit;
      if (_statusIsError) {
        _statusIsError = false;
        _statusMessage = '';
      }
    });
    if (_input.length == _kPinLength) _onConfirm();
  }

  void _onDelete() {
    if (_input.isEmpty || _busy) return;
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  void _onClear() {
    if (_input.isEmpty || _busy) return;
    setState(() => _input = '');
  }

  String _titleForCurrentStep() {
    final l = AppLocalizations.of(context);
    switch (widget._flow) {
      case _PinFlow.verify:
        return l.pinVerifyTitle;
      case _PinFlow.setup:
        return _setupStep == _SetupStep.enter
            ? l.pinPromptSetupEnter
            : l.pinPromptSetupConfirm;
      case _PinFlow.change:
        if (!_changeVerified) return l.pinPromptChangeEnter;
        return _setupStep == _SetupStep.enter
            ? l.pinPromptChangeNew
            : l.pinPromptChangeConfirm;
    }
  }

  Future<void> _onConfirm() async {
    if (!_isValid) return;
    setState(() => _busy = true);
    try {
      switch (widget._flow) {
        case _PinFlow.verify:
          await _handleVerify();
          break;
        case _PinFlow.setup:
          await _handleSetupStep();
          break;
        case _PinFlow.change:
          if (!_changeVerified) {
            await _handleChangeVerify();
          } else {
            await _handleSetupStep();
          }
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleVerify() async {
    final outcome = await _orch.unlockWithPin(_input);
    if (!mounted) return;
    switch (outcome) {
      case UnlockOutcome.success:
        // Unlock immediately so the home screen rebuilds while the pop
        // animation is still running — the user sees stacks as the PIN
        // screen slides away instead of after it fully dismisses.
        AppHaptics.medium();
        context.read<StacksLockController>().unlock();
        Navigator.of(context).pop(true);
      case UnlockOutcome.wrongCredential:
        await _registerWrongPin();
      case UnlockOutcome.corruptBlob:
        // The wrap unwrapped a DEK but the stacks blob failed its MAC check.
        // The data is unrecoverable; pop with a sentinel the caller can
        // handle by routing to the destructive reset flow.
        Navigator.of(context).pop(_kCorruptSentinel);
    }
  }

  Future<void> _handleChangeVerify() async {
    // For change-PIN we still need to validate the OLD pin and obtain the
    // DEK so we can rewrap under the NEW pin in _handleSetupStep. Use the
    // crypto service directly; if there is no wrap yet (legacy users who
    // had a PIN before encryption shipped), fall back to the auth service
    // and migrate after the new PIN is confirmed.
    if (await _crypto.hasPinWrappedDek()) {
      final dek = await _crypto.unwrapDekWithPin(_input);
      if (!mounted) return;
      if (dek == null) {
        await _registerWrongPin();
        return;
      }
      _changeOldDek = dek;
    } else {
      final ok = await _service.verifyPin(_input);
      if (!mounted) return;
      if (!ok) {
        await _registerWrongPin();
        return;
      }
      _changeOldDek = null; // legacy path; init new wrap in _commitNewPin
    }
    setState(() {
      _changeVerified = true;
      _input = '';
      _setupStep = _SetupStep.enter;
      _statusMessage = '';
      _statusIsError = false;
    });
  }

  Future<void> _handleSetupStep() async {
    if (_setupStep == _SetupStep.enter) {
      _firstPinDuringSetup = _input;
      setState(() {
        _input = '';
        _setupStep = _SetupStep.confirm;
        _statusMessage = '';
        _statusIsError = false;
      });
      return;
    }
    // confirm step
    if (_input != _firstPinDuringSetup) {
      _firstPinDuringSetup = null;
      setState(() {
        _setupStep = _SetupStep.enter;
        _statusMessage = AppLocalizations.of(context).pinErrorMismatch;
        _statusIsError = true;
      });
      _shakeAndClear();
      return;
    }
    if (widget._flow == _PinFlow.change) {
      // Re-wrap (or, for legacy users without a wrap yet, init).
      if (_changeOldDek != null) {
        await _crypto.rewrapPin(_changeOldDek!, _input);
      } else {
        // Legacy path: no wrap existed. Mint one and adopt — current stacks
        // are still plaintext on disk, so adoptDek will write the envelope
        // for the first time.
        await _orch.initPinMode(_input);
      }
      // Keep the auth service hash in sync so the cooldown plumbing keeps
      // working consistently.
      await _service.setPin(_input);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    // setup flow
    if (widget._collectOnly) {
      // Caller (mode transition) will perform the rewrap itself.
      Navigator.of(context).pop(_input);
      return;
    }
    // First-time PIN setup: mint a DEK and migrate stacks.
    await _service.setPin(_input);
    await _orch.initPinMode(_input);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _registerWrongPin() async {
    final count = await _service.registerFailure();
    if (!mounted) return;
    _shakeAndClear();
    final cooldown = StacksAuthService.cooldownFor(count);
    if (cooldown != null) {
      _startCooldown(cooldown);
      return;
    }
    final remaining = StacksAuthService.kFailuresBeforeCooldown - count;
    final l = AppLocalizations.of(context);
    final message = remaining <= 2
        ? l.pinErrorWrongAttemptsRemaining(remaining)
        : l.pinErrorWrong;
    _setStatus(message, error: true);
  }

  void _startCooldown(Duration duration) {
    setState(() {
      _cooldownRemaining = duration;
      _statusIsError = true;
      _statusMessage = _cooldownLabel(duration);
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = _cooldownRemaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        t.cancel();
        setState(() {
          _cooldownRemaining = Duration.zero;
          _statusIsError = false;
          _statusMessage = '';
        });
        return;
      }
      setState(() {
        _cooldownRemaining = next;
        _statusMessage = _cooldownLabel(next);
      });
    });
  }

  String _cooldownLabel(Duration remaining) {
    final l = AppLocalizations.of(context);
    final totalSeconds = remaining.inSeconds;
    if (totalSeconds < 60) {
      return l.pinCooldownSeconds(totalSeconds);
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return l.pinCooldownMinutes(minutes, seconds);
  }

  @override
  Widget build(BuildContext context) {
    final dotCount = _kPinLength;
    final screenTitle = widget.title ?? _titleForCurrentStep();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CancelBar(onCancel: () => Navigator.of(context).maybePop(false)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      screenTitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.title,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AnimatedBuilder(
                      animation: _shakeCtrl,
                      builder: (context, child) {
                        final t = _shakeCtrl.value;
                        final dx = t == 0 ? 0.0 : sin(t * pi * 8) * 10 * (1 - t);
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: child,
                        );
                      },
                      child: _PinDots(
                        filled: _input.length,
                        total: dotCount,
                        checking: _busy,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(
                        color: _statusIsError ? cs.error : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              NumberPad(
                onInput: _onInput,
                onDelete: _onDelete,
                onClear: _onClear,
                onEnter: _onConfirm,
                isValid: _isValid,
                isEmpty: _input.isEmpty,
                showConfirm: false,
                showDecimal: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatefulWidget {
  const _PinDots({
    required this.filled,
    required this.total,
    required this.checking,
  });

  final int filled;
  final int total;

  /// While true (PIN submitted, KDF running) the dots pulse in a staggered
  /// wave to acknowledge the input — without claiming it's correct.
  final bool checking;

  @override
  State<_PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<_PinDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.checking) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_PinDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checking && !oldWidget.checking) {
      _pulse.repeat();
    } else if (!widget.checking && oldWidget.checking) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  double _scaleFor(int i) {
    if (!widget.checking) return 1.0;
    final phase = (_pulse.value - i / widget.total) % 1.0;
    return 1.0 - 0.3 * sin(phase * pi);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.total; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Transform.scale(
              scale: _scaleFor(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: i < widget.filled
                      ? p.bitcoinOrange
                      : Colors.transparent,
                  border: Border.all(
                    color: i < widget.filled
                        ? p.bitcoinOrange
                        : cs.onSurfaceVariant,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
