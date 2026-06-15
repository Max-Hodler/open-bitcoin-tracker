import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../data/app_enums.dart';
import '../../../data/fiat.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../../widgets/rolling_number.dart';

class CurrentPrice extends StatefulWidget {
  const CurrentPrice({
    super.key,
    required this.price,
    required this.hover,
    required this.lastFetchedAt,
    required this.range,
    required this.currency,
    required this.selectedCurrencies,
    required this.rollDirection,
    required this.onPriceTap,
    required this.onCurrencySwipe,
    required this.chartColor,
    required this.showChart,
    this.rangePct,
    this.rangeAbsDiff,
  });

  final double price;
  final ValueListenable<PricePoint?> hover;
  final DateTime? lastFetchedAt;
  final BtcRange range;
  final Currency currency;
  // The user's swipe-cycle ring. We need it locally (not just via the parent
  // callback) so we know whether a swipe will actually advance the currency —
  // only then is it correct to record a pending slide direction.
  final List<Currency> selectedCurrencies;
  final int rollDirection;
  final VoidCallback onPriceTap;
  final ValueChanged<int> onCurrencySwipe;
  final Color chartColor;
  final bool showChart;
  final double? rangePct;
  final double? rangeAbsDiff;

  @override
  State<CurrentPrice> createState() => _CurrentPriceState();
}

class _CurrentPriceState extends State<CurrentPrice>
    with TickerProviderStateMixin {
  /// Direction the new currency tile slides in from on a currency change.
  /// +1 = enters from the right (user swiped left / "next");
  /// -1 = enters from the left (user swiped right / "previous").
  ///
  /// Resolved in [didUpdateWidget] from one of three signals, in priority
  /// order:
  ///
  ///   1. **Swipe gesture** — the swipe handler sets [_pendingSwipeDir] just
  ///      before calling `setCurrency`. didUpdateWidget consumes it. This is
  ///      always right because the user's intent is encoded directly.
  ///
  ///   2. **Picker-driven change** — no gesture, no _pendingSwipeDir. We fall
  ///      back to shortest-path in [Currency.values] enum order.
  ///
  ///   3. **Honest disclaimer** — the user's `selectedCurrencies` ring is a
  ///      runtime-ordered subset; enum-order shortest path can pick the
  ///      "wrong" direction on a non-monotonic ring (e.g. ring [USD, JPY, EUR]
  ///      moving from USD→EUR animates leftward even though "next in ring"
  ///      means rightward). Only matters for the cross-fade direction on the
  ///      first frame, so it's an aesthetic miss, not a correctness bug.
  int _slideDir = 1;

  /// Set by the swipe handler immediately before it triggers a currency
  /// change upstream. The next [didUpdateWidget] consumes it; see
  /// [_slideDir] for the full resolution flow.
  int? _pendingSwipeDir;

  // The price actually rendered by RollingNumber. Mirrors widget.price; kept
  // as separate state so a hover scrub doesn't clobber it and we can snap it
  // forward on currency switches without fighting the listenable.
  double? _renderedPrice;

  // Active delta state. _deltaValue is the signed change (in display
  // currency) currently shown as the subtitle; _deltaFade drives a single
  // fade-in / hold / fade-out cycle.
  //
  // Eager-init in initState rather than `late final … vsync: this` because
  // lazy-initializing inside dispose() — which happens when the widget is
  // disposed before any tick triggers _showDelta() — tries to bind a ticker
  // against a deactivated element and throws "Looking up a deactivated
  // widget's ancestor is unsafe."
  double? _deltaValue;
  Timer? _deltaHoldTimer;
  late final AnimationController _deltaFade;

  static const Duration _kDeltaHold = Duration(milliseconds: 2000);
  static const Duration _kDeltaFadeDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _renderedPrice = widget.price;
    _deltaFade = AnimationController(
      vsync: this,
      duration: _kDeltaFadeDuration,
    );
  }

  @override
  void didUpdateWidget(covariant CurrentPrice old) {
    super.didUpdateWidget(old);
    if (old.currency != widget.currency) {
      final pending = _pendingSwipeDir;
      _pendingSwipeDir = null;
      if (pending != null) {
        _slideDir = pending;
      } else {
        // Picker-driven change (no gesture): fall back to enum-order shortest
        // path. Imperfect for non-monotonic ring orders but only matters for
        // the first frame of the cross-fade.
        const values = Currency.values;
        final oldI = values.indexOf(old.currency);
        final newI = values.indexOf(widget.currency);
        final forward = (newI - oldI) % values.length;
        final backward = (oldI - newI) % values.length;
        _slideDir = forward <= backward ? 1 : -1;
      }
      _cancelDelta();
      _renderedPrice = widget.price;
      return;
    }
    if (old.price != widget.price) {
      // Skip the delta on the first real price (0 → first fetched value).
      final wasZero = (old.price == 0) || (_renderedPrice ?? 0) == 0;
      final prevRendered = _renderedPrice ?? old.price;
      _renderedPrice = widget.price;
      if (wasZero) {
        _cancelDelta();
        return;
      }
      _showDelta(widget.price - prevRendered);
    }
  }

  void _showDelta(double delta) {
    if (delta == 0) return;
    _deltaHoldTimer?.cancel();
    _deltaFade.stop();
    setState(() {
      _deltaValue = delta;
      _deltaFade.value = 0;
    });
    _deltaFade.forward();
    _deltaHoldTimer = Timer(_kDeltaHold, () {
      if (!mounted) return;
      _deltaFade.reverse().whenComplete(() {
        if (!mounted) return;
        setState(() => _deltaValue = null);
      });
    });
  }

  void _cancelDelta() {
    _deltaHoldTimer?.cancel();
    _deltaFade.stop();
    if (_deltaValue != null) {
      setState(() => _deltaValue = null);
    }
  }

  @override
  void dispose() {
    _deltaHoldTimer?.cancel();
    _deltaFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Tabular figures force every digit (0-9) to share an advance width, so
    // RollingNumber's per-digit cell — which uses TextPainter('0').width as
    // the slot width — lines up with the natural text baseline instead of
    // wiggling as proportional digits roll past.
    final priceStyle = AppTypography.display.copyWith(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: cs.onSurface.withValues(alpha: 0.92),
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    // Pin the price-row height so a digit roll or currency swap can never
    // reflow the column (which would push the chart below). Measured from
    // the same style RollingNumber uses internally, so the pinned outer
    // height and the digit cells agree on metrics.
    final priceRowHeight = DigitCellMetrics.of(
      priceStyle,
      MediaQuery.textScalerOf(context),
    ).height;
    return ValueListenableBuilder<PricePoint?>(
      valueListenable: widget.hover,
      builder: (context, h, _) {
        final displayPrice = h?.price ?? (_renderedPrice ?? widget.price);
        final hoverLabel = h != null ? _formatHoverLabel(h.t, widget.range) : null;
        // Hide the delta while the user scrubs the chart — the subtitle shows
        // the hover timestamp instead. Also respect the user setting.
        final showDeltaSetting = context.select<AppStateNotifier, bool>(
          (a) => a.showPriceDelta,
        );
        final showDelta = h == null && _deltaValue != null && showDeltaSetting;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            final vx = details.primaryVelocity ?? 0;
            if (vx.abs() < 200) return;
            final dir = vx < 0 ? 1 : -1;
            // Only record a pending slide direction when a swipe will actually
            // advance the cycle. With ≤1 selected, the parent opens the picker
            // instead — and the eventual currency change there shouldn't be
            // animated as if it were the swipe we just made.
            if (widget.selectedCurrencies.length >= 2) {
              _pendingSwipeDir = dir;
            }
            widget.onCurrencySwipe(dir);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  AppHaptics.selection();
                  widget.onPriceTap();
                },
                onLongPress: kDebugMode
                    ? () {
                        AppHaptics.heavy();
                        context
                            .read<LivePriceController>()
                            .debugSimulateTick();
                      }
                    : null,
                child: SizedBox(
                  height: priceRowHeight,
                  child: AnimatedSwitcher(
                    duration: AppSpacing.motionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, anim) {
                      final isIncoming =
                          child.key == ValueKey(widget.currency.code);
                      final begin = Offset(
                        (isIncoming ? 1.0 : -1.0) * _slideDir * 0.25, 0,
                      );
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: begin,
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      );
                    },
                    child: RollingNumber(
                      key: ValueKey(widget.currency.code),
                      text: formatFiat(displayPrice, widget.currency).tight,
                      direction: widget.rollDirection,
                      // Snap (don't roll) while the user is scrubbing the
                      // chart; hover supplies displayPrice and rolling each
                      // scrubbed value would be distracting. RollingNumber's
                      // didUpdate also handles the lift-off
                      // (animate=false → true) by snapping straight to the
                      // live value.
                      animate: h == null,
                      style: priceStyle,
                    ),
                  ),
                ),
              ),
              _PriceSubtitle(
                hoverLabel: hoverLabel,
                deltaValue: showDelta ? _deltaValue : null,
                currency: widget.currency,
                fade: _deltaFade,
                rangePct: (h == null && widget.showChart && widget.range != BtcRange.all) ? widget.rangePct : null,
                rangeAbsDiff: (h == null && widget.showChart && widget.range != BtcRange.all) ? widget.rangeAbsDiff : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Subtitle line below the live price. Shows the hover timestamp while the
/// user scrubs the chart, the signed price delta when a tick arrives, the
/// range % change when idle, or an empty line so the column height stays stable.
class _PriceSubtitle extends StatelessWidget {
  const _PriceSubtitle({
    required this.hoverLabel,
    required this.deltaValue,
    required this.currency,
    required this.fade,
    required this.rangePct,
    required this.rangeAbsDiff,
  });

  final String? hoverLabel;
  final double? deltaValue;
  final Currency currency;
  final Animation<double> fade;
  final double? rangePct;
  final double? rangeAbsDiff;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseStyle = AppTypography.body.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 15,
    );
    if (hoverLabel != null) {
      return Text(hoverLabel!, style: baseStyle);
    }

    Widget? deltaWidget;
    if (deltaValue != null) {
      final p = context.palette;
      final isPositive = deltaValue! >= 0;
      final color = isPositive ? p.priceUp : p.priceDown;
      final symbol = currencySymbols[currency] ?? r'$';
      final amount = _numberFormat('#,##0.00').format(deltaValue!.abs());
      final body = '${isPositive ? '+' : '-'}'
          '${symbolAfterAmount ? '$amount$symbol' : '$symbol$amount'}';
      deltaWidget = AnimatedBuilder(
        animation: fade,
        builder: (context, _) {
          return Opacity(
            opacity: Curves.easeOut.transform(fade.value),
            child: Text(body, style: baseStyle.copyWith(color: color)),
          );
        },
      );
    }

    if (rangeAbsDiff != null || rangePct != null) {
      final absPart = rangeAbsDiff != null
          ? _formatRangeAbsDiff(rangeAbsDiff!, currency)
          : '';
      final pctPart = rangePct != null ? _formatRangePct(rangePct!) : '';
      final label = absPart.isNotEmpty && pctPart.isNotEmpty
          ? '$absPart ($pctPart)'
          : absPart.isNotEmpty
              ? absPart
              : pctPart;
      if (deltaWidget == null) {
        return Text(label, style: baseStyle);
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: baseStyle),
          const SizedBox(width: 8),
          deltaWidget,
        ],
      );
    }

    if (deltaWidget != null) return deltaWidget;
    return Text('', style: baseStyle);
  }
}

// Formatter construction does a locale lookup and pattern parse each time,
// and these run per tick (subtitle/delta) and per hover update (scrub
// label). Cache per (pattern, locale); the key set is small and bounded
// (fixed patterns — the dynamic-decimals pct pattern tops out at 8 — ×
// supported locales), so no eviction is needed.
final Map<(String, String?), NumberFormat> _numberFormats = {};

NumberFormat _numberFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _numberFormats[(pattern, locale)] ??= NumberFormat(pattern, locale);
}

final Map<(String, String?), DateFormat> _dateFormats = {};

DateFormat _dateFormat(String skeleton, DateFormat Function() create) =>
    _dateFormats[(skeleton, Intl.defaultLocale)] ??= create();

String _formatRangeAbsDiff(double diff, Currency currency) {
  final sign = diff >= 0 ? '+' : '-';
  final abs = diff.abs();
  final symbol = currencySymbols[currency] ?? r'$';
  final formatted = _numberFormat('#,##0').format(abs.round());
  final after = symbolAfterAmount;
  return '$sign${after ? '$formatted$symbol' : '$symbol$formatted'}';
}

String _formatRangePct(double pct) {
  final sign = pct < 0 ? '-' : '+';
  final abs = pct.abs();
  if (abs >= 1000000) return '$sign${(abs / 1000000).round()}M%';
  if (abs >= 1000) return '$sign${(abs / 1000).round()}K%';
  if (abs >= 0.5) {
    return '$sign${_numberFormat('#,##0').format(abs.round())}%';
  }
  if (abs == 0) return '+0.0%';
  var decimals = 1;
  while (decimals < 8 && (abs * _pow10(decimals)).round() == 0) {
    decimals++;
  }
  return '$sign${_numberFormat('#,##0.${'0' * decimals}').format(abs)}%';
}

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

String _formatHoverLabel(int ms, BtcRange range) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  switch (range) {
    case BtcRange.d1:
    case BtcRange.d2:
    case BtcRange.d3:
    case BtcRange.d4:
    case BtcRange.d5:
    case BtcRange.d6:
    case BtcRange.d7:
      return _dateFormat('Hm', DateFormat.Hm).format(d);
    case BtcRange.w1:
    case BtcRange.w2:
    case BtcRange.w3:
    case BtcRange.w4:
    case BtcRange.m1:
    case BtcRange.m2:
    case BtcRange.m3:
    case BtcRange.m4:
    case BtcRange.m5:
    case BtcRange.m6:
    case BtcRange.m7:
    case BtcRange.m8:
    case BtcRange.m9:
    case BtcRange.m10:
    case BtcRange.m11:
    case BtcRange.m12:
      // Full month name, no time — day precision is enough for week/month ranges.
      return _dateFormat('MMMMd', DateFormat.MMMMd).format(d);
    case BtcRange.y1:
    case BtcRange.y2:
    case BtcRange.y3:
    case BtcRange.y4:
    case BtcRange.y5:
    case BtcRange.y6:
    case BtcRange.y7:
    case BtcRange.y8:
    case BtcRange.y9:
    case BtcRange.y10:
    case BtcRange.y11:
    case BtcRange.y12:
    case BtcRange.y13:
    case BtcRange.y14:
    case BtcRange.y15:
    case BtcRange.all:
      return _dateFormat('yMMMd', DateFormat.yMMMd).format(d);
  }
}

