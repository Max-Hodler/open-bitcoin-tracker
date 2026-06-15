import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/blinking_caret.dart';
import '../../widgets/number_pad.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Slot model
//
// Each mode has a "top" slot and a "bottom" slot. Their meaning:
//
//   Mode \ Slot      top                          bottom
//   ─────────────────────────────────────────────────────────────────────
//   fiat             fiat (currency)              Bitcoin (sats or BTC)
//   sats             sats                         BTC
//
// The user types into the active slot; the other is derived at render time
// from the live BTC price (fiat mode) or from a pure unit conversion (sats
// mode). The display unit of the Bitcoin-side slot is the converter's
// own [BtcDisplayMode] in fiat mode, and always BTC in sats mode.
// ─────────────────────────────────────────────────────────────────────────────

class ConverterScreen extends StatelessWidget {
  const ConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<ConverterState>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final notifier = context.read<AppStateNotifier>();

    // Hydrate persisted state and install persistence hook on first build.
    // Both are idempotent: hydrateOnce guards on its own flag, onPersist
    // uses ??=. Safe to call unconditionally from build.
    cs.hydrateOnce(
      fiat: entryFrom(
        notifier.converterFiatModeRaw,
        notifier.converterFiatModeActiveSlot,
      ),
      sats: entryFrom(
        notifier.converterSatsModeRaw,
        notifier.converterSatsModeActiveSlot,
      ),
      mode: parseMode(notifier.converterMode) ?? ConverterMode.fiat,
    );
    cs.onPersist ??= (mode, entry) {
      final write = mode == ConverterMode.fiat
          ? notifier.setConverterFiatModeEntry
          : notifier.setConverterSatsModeEntry;
      write(raw: entry.raw, activeSlot: entry.active.name);
    };
    cs.onPersistMode ??= (mode) => notifier.setConverterMode(mode.name);

    // Resolve currency + Bitcoin display unit. First-visit fallback uses the
    // app-wide settings; subsequent visits use the converter's own choices.
    final persistedCurrency = context.select<AppStateNotifier, Currency?>(
      (a) => a.converterCurrency,
    );
    final persistedBtcMode =
        context.select<AppStateNotifier, BtcDisplayMode?>(
      (a) => a.converterBtcMode,
    );
    final homeCurrency = notifier.currency;
    final globalBtcMode = notifier.btcDisplayMode;
    final currency = persistedCurrency ?? homeCurrency;
    // Persist the seed after the frame so subsequent visits skip this path.
    if (persistedCurrency == null || persistedBtcMode == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (notifier.converterCurrency == null) {
          notifier.setConverterCurrency(homeCurrency);
        }
        if (notifier.converterBtcMode == null) {
          notifier.setConverterBtcMode(globalBtcMode);
        }
      });
    }

    final rate = context.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(currency),
        ) ??
        0;
    final isSatsMode = cs.mode == ConverterMode.sats;
    // In sats mode the bottom slot is always BTC. In fiat mode it follows
    // the converter's own display setting.
    final btcMode =
        isSatsMode ? BtcDisplayMode.btc : (persistedBtcMode ?? globalBtcMode);

    // Derive both slots' raw strings. The active slot is verbatim; the other
    // is computed from it. Returns ('' '') when there's nothing useful to
    // show (rate unavailable in fiat mode, etc.).
    final raws = deriveRaws(
      mode: cs.mode,
      active: cs.active,
      raw: cs.raw,
      btcMode: btcMode,
      rate: rate,
    );

    return TickerMode(
      enabled: ModalRoute.of(context)?.isCurrent ?? true,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: scheme.surfaceContainerLow,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: BackButton(color: scheme.onSurfaceVariant),
          centerTitle: true,
          title: Text(
            l10n.homeConverter,
            style: AppTypography.title.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              _ModeToggle(
                mode: cs.mode,
                onChanged: (m) => cs.setMode(m),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SlotView(
                        unit: slotUnit(cs.mode, ConverterSlot.top, btcMode),
                        currency: currency,
                        raw: raws.top,
                        active: cs.active == ConverterSlot.top,
                        caret: cs.active == ConverterSlot.top ? cs.caret : 0,
                        onActivate: () =>
                            _activate(cs, ConverterSlot.top, rate, btcMode),
                        onCaretAt: (i) => cs.edit(caret: i),
                        onCopy: () => _copy(context, raws.top),
                        onLabelTap: isSatsMode
                            ? null
                            : () => _openCurrencyPicker(context),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _ArrowStack(),
                      const SizedBox(height: AppSpacing.sm),
                      _SlotView(
                        unit: slotUnit(cs.mode, ConverterSlot.bottom, btcMode),
                        currency: currency,
                        raw: raws.bottom,
                        active: cs.active == ConverterSlot.bottom,
                        caret: cs.active == ConverterSlot.bottom ? cs.caret : 0,
                        onActivate: () =>
                            _activate(cs, ConverterSlot.bottom, rate, btcMode),
                        onCaretAt: (i) => cs.edit(caret: i),
                        onCopy: () => _copy(context, raws.bottom),
                        onLabelTap: isSatsMode
                            ? null
                            : () => _openBtcUnitPicker(context),
                      ),
                    ],
                  ),
                ),
              ),
              // Leading-zero warning sits just above the keypad so it lands in
              // the user's eye-line as they tap the disabled '0' key. The
              // 20px slot is always reserved so toggling the warning doesn't
              // bump the keypad down.
              SizedBox(
                height: 20,
                child: cs.showLeadingZeroWarning
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.satsInputLeadingZeroWarning,
                          style: AppTypography.label.copyWith(
                            letterSpacing: 1.5,
                            color: scheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              NumberPad(
                showConfirm: false,
                showDecimal: activeAllowsDecimal(cs.mode, cs.active, btcMode),
                decimalLabel: localeDecimalSeparator,
                onInput: (v) => _onInput(cs, v, btcMode),
                onDelete: () => _onDelete(cs),
                onClear: () => _onClear(cs),
                onEnter: () {},
                isValid: false,
                isEmpty: cs.raw.isEmpty,
                zeroDisabled:
                    leadingZeroBlocked(cs.mode, cs.active, cs.raw, btcMode),
                onZeroBlocked: () => cs.edit(warning: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onInput(ConverterState cs, String v, BtcDisplayMode btcMode) {
    final unit = slotUnit(cs.mode, cs.active, btcMode);
    final result = insertChar(cs.raw, cs.caret, v, unit);
    if (result == null) {
      // Insert rejected. The sats-side leading-zero rule still needs to
      // surface its warning even when the keypad's zeroDisabled gate didn't
      // fire (e.g. typing '0' at caret 0 with non-empty input).
      if (v == '0' &&
          unit == ConverterInputUnit.sats &&
          cs.caret == 0 &&
          cs.raw.isNotEmpty) {
        cs.edit(warning: true);
      }
      return;
    }
    cs.edit(raw: result.$1, caret: result.$2, warning: false);
  }

  void _onDelete(ConverterState cs) {
    if (cs.raw.isEmpty || cs.caret == 0) return;
    final next = cs.raw.substring(0, cs.caret - 1) + cs.raw.substring(cs.caret);
    cs.edit(raw: next, caret: cs.caret - 1);
  }

  void _onClear(ConverterState cs) {
    if (cs.raw.isEmpty) return;
    cs.edit(raw: '', caret: 0, warning: false);
  }

  /// Switches the active slot. Converts the existing raw into the new slot's
  /// unit so the displayed numbers don't visually jump, and the next
  /// keystroke appends to the now-active value.
  void _activate(
    ConverterState cs,
    ConverterSlot slot,
    double rate,
    BtcDisplayMode btcMode,
  ) {
    if (cs.active == slot) return;
    AppHaptics.selection();
    final isSatsMode = cs.mode == ConverterMode.sats;
    // Empty input, or fiat-mode without a rate, just flips the active slot.
    if (cs.raw.isEmpty || (!isSatsMode && rate <= 0)) {
      cs.edit(active: slot, warning: false);
      return;
    }
    final fromUnit = slotUnit(cs.mode, cs.active, btcMode);
    final toUnit = slotUnit(cs.mode, slot, btcMode);
    final sats = rawToSats(cs.raw, fromUnit, rate);
    final converted = satsToRaw(sats, toUnit, rate);
    cs.edit(active: slot, raw: converted, warning: false);
  }

  /// Opens the currency picker. Persists into the converter's own field —
  /// the home-screen currency and swipe ring stay untouched.
  Future<void> _openCurrencyPicker(BuildContext context) async {
    final notifier = context.read<AppStateNotifier>();
    final current = notifier.converterCurrency ?? notifier.currency;
    final picked = await showModalBottomSheet<Currency>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _CurrencySheet(current: current),
    );
    if (picked == null || picked == current) return;
    notifier.setConverterCurrency(picked);
  }

  /// Opens the Bitcoin display-unit picker. Migrates the live fiat-mode
  /// snapshot synchronously **before** persisting the new setting, so the
  /// next rebuild sees a coherent (raw, display-unit) pair in one step.
  /// No post-frame syncing, no race.
  Future<void> _openBtcUnitPicker(BuildContext context) async {
    final notifier = context.read<AppStateNotifier>();
    final cs = context.read<ConverterState>();
    final current =
        notifier.converterBtcMode ?? notifier.btcDisplayMode;
    final picked = await showModalBottomSheet<BtcDisplayMode>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _BtcUnitSheet(current: current),
    );
    if (picked == null || picked == current) return;
    cs.migrateFiatBtcDisplay(current, picked);
    notifier.setConverterBtcMode(picked);
  }

  /// Copies the canonical numeric form of [raw] to the clipboard.
  Future<void> _copy(BuildContext context, String raw) async {
    if (raw.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: raw));
    AppHaptics.medium();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Copied $raw'),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slot view — label + card. Encapsulates the (mode, slot, btcMode) →
// (label, prefix, suffix, allowed-decimal) decoding so the parent stays flat.
// ─────────────────────────────────────────────────────────────────────────────

class _SlotView extends StatelessWidget {
  const _SlotView({
    required this.unit,
    required this.currency,
    required this.raw,
    required this.active,
    required this.caret,
    required this.onActivate,
    required this.onCaretAt,
    required this.onCopy,
    required this.onLabelTap,
  });

  final ConverterInputUnit unit;
  final Currency currency;
  final String raw;
  final bool active;
  final int caret;
  final VoidCallback onActivate;
  final ValueChanged<int> onCaretAt;
  final VoidCallback onCopy;
  final VoidCallback? onLabelTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final String labelText;
    switch (unit) {
      case ConverterInputUnit.fiat:
        labelText = currency.code.toUpperCase();
      case ConverterInputUnit.sats:
        labelText = 'BITCOIN (${l10n.bitcoinDisplayModeSats.toUpperCase()})';
      case ConverterInputUnit.btc:
        labelText = 'BITCOIN (${l10n.bitcoinDisplayModeBtc.toUpperCase()})';
    }

    final symbol = currencySymbols[currency] ?? r'$';
    final String prefix;
    final String? suffix;
    switch (unit) {
      case ConverterInputUnit.fiat:
        prefix = symbolAfterAmount ? '' : symbol;
        suffix = symbolAfterAmount ? symbol : null;
      case ConverterInputUnit.sats:
      case ConverterInputUnit.btc:
        prefix = symbolAfterAmount ? '' : '₿';
        suffix = symbolAfterAmount ? '₿' : null;
    }

    // Sats raw is a pure digit string; everything else may contain a decimal
    // separator. formatFiatRaw handles both cleanly (it routes through
    // groupDigits for integer-only and splits/regroups around the '.').
    final display = unit == ConverterInputUnit.sats ? groupDigits(raw) : formatFiatRaw(raw);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabelRow(
          text: labelText,
          color: scheme.onSurfaceVariant,
          onTap: onLabelTap,
        ),
        const SizedBox(height: 4),
        _Card(
          prefix: prefix,
          suffix: suffix,
          value: display,
          raw: raw,
          caret: caret,
          active: active,
          onTap: onActivate,
          onLongPress: onCopy,
          onCaretAt: active ? onCaretAt : null,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Underlined segmented control: Fiat-BTC / Sats-BTC. The active mode shows
/// a bitcoin-orange underline; the inactive mode renders as plain label text.
class _ModeToggle extends StatefulWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final ConverterMode mode;
  final ValueChanged<ConverterMode> onChanged;

  @override
  State<_ModeToggle> createState() => _ModeToggleState();
}

class _ModeToggleState extends State<_ModeToggle> {
  static const int _tabCount = 2;
  final List<GlobalKey> _tabKeys =
      List.generate(_tabCount, (_) => GlobalKey());
  final GlobalKey _stackKey = GlobalKey();

  List<Rect> _tabRects = const [];

  void _measureTabs() {
    final stackBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;
    final rects = <Rect>[];
    for (final key in _tabKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final topLeft =
          stackBox.globalToLocal(box.localToGlobal(Offset.zero));
      rects.add(topLeft & box.size);
    }
    if (!_rectsEqual(rects, _tabRects)) {
      setState(() => _tabRects = rects);
    }
  }

  static bool _rectsEqual(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final palette = context.palette;
    final trackFill =
        palette.recessedSurface ?? cs.surfaceContainer;

    final selectedIndex = widget.mode == ConverterMode.fiat ? 0 : 1;
    final selectedRect = selectedIndex < _tabRects.length
        ? _tabRects[selectedIndex]
        : null;

    const trackPadding = 2.0;

    Widget tabSlot(int index, String label) {
      final selected = index == selectedIndex;
      return Expanded(
        child: Center(
          child: KeyedSubtree(
            key: _tabKeys[index],
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: selected
                  ? null
                  : () {
                      AppHaptics.light();
                      widget.onChanged(
                        index == 0 ? ConverterMode.fiat : ConverterMode.sats,
                      );
                    },
              child: Container(
                constraints: const BoxConstraints(minWidth: 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? palette.bitcoinOrange
                        : cs.onSurfaceVariant,
                  ),
                  child: Text(label, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTabs());

    return Stack(
      children: [
        // Recessed track
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: trackFill,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(trackPadding),
          child: Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: [
              // Sliding pill
              if (selectedRect != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: selectedRect.left,
                  top: selectedRect.top,
                  width: selectedRect.width,
                  height: selectedRect.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          offset: const Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              // Tab row on top of pill
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  tabSlot(0, l10n.converterModeBtcFiat),
                  tabSlot(1, l10n.converterModeBtcSats),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({
    required this.prefix,
    required this.value,
    required this.raw,
    required this.caret,
    required this.active,
    required this.onTap,
    this.onLongPress,
    this.onCaretAt,
    this.suffix,
  });

  final String prefix;
  // Formatted display: locale-grouped, with the locale's decimal separator
  // on fiat. What the user sees.
  final String value;
  // Canonical raw value: '.'-separated for fiat/BTC, digits-only for sats.
  // Used as the BlinkingCaret's keystroke signal.
  final String raw;
  // Caret position in [raw], in [0, raw.length]. Only meaningful when active.
  final int caret;
  final String? suffix;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  // Called when the user taps a character; places the caret to that char's
  // left. End-of-input is reachable via the card-tap InkWell.
  final ValueChanged<int>? onCaretAt;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  // Recognizer pool, one per per-character tap. Disposed in [dispose].
  final List<TapGestureRecognizer> _recognizers = [];

  TapGestureRecognizer _recognizerAt(int i, VoidCallback onTap) {
    while (_recognizers.length <= i) {
      _recognizers.add(TapGestureRecognizer());
    }
    _recognizers[i].onTap = onTap;
    return _recognizers[i];
  }

  void _trimRecognizers(int keepCount) {
    while (_recognizers.length > keepCount) {
      _recognizers.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        widget.active ? scheme.surfaceContainerHigh : scheme.surface;
    final fg = scheme.onSurface;
    const fontSize = 28.0;
    final numberStyle = TextStyle(
      fontFamily: AppTypography.sansFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      color: fg,
    );
    final localeSep = localeDecimalSeparator;
    // Caret is rendered with zero layout width so moving it between digits
    // doesn't shift the surrounding glyphs by the caret's 2px stroke. The
    // OverflowBox lets it paint outside its 0-width slot.
    final caretWidget = SizedBox(
      width: 0,
      height: fontSize * 1.2,
      child: OverflowBox(
        maxWidth: 2,
        alignment: Alignment.centerLeft,
        child: BlinkingCaret(
          color: fg,
          height: fontSize * 1.2,
          keystrokeSignal: '${widget.raw}|${widget.caret}',
        ),
      ),
    );

    // Build the value display. When active, a single shaped Text.rich
    // paragraph with per-char TextSpan tap recognizers (so spacing matches
    // the inactive Text(value) exactly). When inactive, plain Text — a tap
    // on the card activates this slot via the InkWell.
    final Widget valueWidget;
    if (widget.active && widget.value.isEmpty) {
      // Empty active side: 2px-wide caret so its stroke paints inside
      // layout bounds.
      valueWidget = SizedBox(
        width: 2,
        height: fontSize * 1.2,
        child: BlinkingCaret(
          color: fg,
          height: fontSize * 1.2,
          keystrokeSignal: '${widget.raw}|${widget.caret}',
        ),
      );
    } else if (widget.active) {
      final spans = <InlineSpan>[];
      final canTap = widget.onCaretAt != null;
      var rawConsumed = 0;
      var recognizerIdx = 0;
      void addCaretIfHere() {
        if (rawConsumed == widget.caret) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: caretWidget,
          ));
        }
      }

      for (var i = 0; i < widget.value.length; i++) {
        final ch = widget.value[i];
        final isDigit = ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
        final isDecimal = ch == localeSep;
        // Group separators (commas, NBSPs, etc.) live between digits in the
        // formatted string but don't exist in raw, so they don't advance
        // the raw cursor.
        if (!isDigit && !isDecimal) {
          spans.add(TextSpan(text: ch));
          continue;
        }
        addCaretIfHere();
        final before = rawConsumed;
        spans.add(TextSpan(
          text: ch,
          recognizer: canTap
              ? _recognizerAt(recognizerIdx++, () => widget.onCaretAt!(before))
              : null,
        ));
        rawConsumed += 1;
      }
      addCaretIfHere();
      _trimRecognizers(recognizerIdx);

      // FittedBox lets very long inputs shrink instead of clipping the
      // right edge of the card. Aligned left so the caret stays where the
      // user expects.
      valueWidget = Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(style: numberStyle, children: spans),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      );
    } else if (widget.value.isNotEmpty) {
      valueWidget = Flexible(
        child: Text(
          widget.value,
          overflow: TextOverflow.ellipsis,
          style: numberStyle,
        ),
      );
    } else {
      // Inactive and empty: reserve the glyph's vertical space so the card
      // doesn't squash to label-height. (Sats-mode bottom card hits this
      // when there's no input — it has no prefix/suffix to hold the row open.)
      valueWidget = const SizedBox(width: 0, height: fontSize * 1.2);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.prefix.isNotEmpty) ...[
                  Text(widget.prefix, style: numberStyle),
                  const SizedBox(width: 4),
                ],
                valueWidget,
                if (widget.suffix != null) ...[
                  const SizedBox(width: 4),
                  Text(widget.suffix!, style: numberStyle),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowStack extends StatelessWidget {
  const _ArrowStack();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.arrow_downward, size: 18, color: scheme.onSurface),
        const SizedBox(width: 2),
        Icon(Icons.arrow_upward, size: 18, color: scheme.onSurface),
      ],
    );
  }
}

/// Bottom-sheet currency picker. Single-select (unlike the multi-select ring
/// in the settings screen), because the converter has exactly one active
/// fiat side at a time.
class _CurrencySheet extends StatelessWidget {
  const _CurrencySheet({required this.current});

  final Currency current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          for (final c in Currency.values)
            ListTile(
              leading: SizedBox(
                width: 24,
                child: c == current
                    ? Icon(Icons.check, color: scheme.primary)
                    : null,
              ),
              title: Text.rich(TextSpan(children: [
                TextSpan(
                  text: c.code,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: ' — ${currencyLabel(l10n, c)}'),
              ])),
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet picker for the converter's local Bitcoin display unit.
class _BtcUnitSheet extends StatelessWidget {
  const _BtcUnitSheet({required this.current});

  final BtcDisplayMode current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    Widget row(BtcDisplayMode m, String label) => ListTile(
          leading: SizedBox(
            width: 24,
            child: m == current
                ? Icon(Icons.check, color: scheme.primary)
                : null,
          ),
          title: Text(label),
          onTap: () => Navigator.of(context).pop(m),
        );
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          row(BtcDisplayMode.sats,
              'Bitcoin (${l10n.bitcoinDisplayModeSats})'),
          row(BtcDisplayMode.btc,
              'Bitcoin (${l10n.bitcoinDisplayModeBtc})'),
        ],
      ),
    );
  }
}

/// Top-of-card label, optionally tappable. When [onTap] is null, renders as
/// plain text matching the previous look. When set, adds a small chevron
/// and becomes its own ink target. Both branches reserve the same bounding
/// box so cards don't shift when the chevron toggles.
class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.text, required this.color, this.onTap});

  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.label.copyWith(
      letterSpacing: 1.5,
      color: color,
      fontWeight: FontWeight.w500,
    );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4)
          .copyWith(left: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(text, style: style),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 16, color: color),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          AppHaptics.selection();
          onTap!();
        },
        child: body,
      ),
    );
  }
}
