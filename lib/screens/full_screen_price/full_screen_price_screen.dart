import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../main.dart' show kDefaultOrientations, kLandscapeOrientations;
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/rolling_number.dart';

/// Full-screen, landscape live-price mode. Shows nothing but the live price
/// filling the screen; tapping anywhere pops back to the home screen.
///
/// The rest of the app may be portrait or landscape; this screen forces
/// landscape while it's on screen and restores the default set on exit — the
/// mirror image of the portrait-only [ConverterScreen]. It also hides the
/// system bars so the price truly owns the whole display.
class FullScreenPriceScreen extends StatefulWidget {
  const FullScreenPriceScreen({super.key, required this.currency});

  final Currency currency;

  @override
  State<FullScreenPriceScreen> createState() => _FullScreenPriceScreenState();
}

class _FullScreenPriceScreenState extends State<FullScreenPriceScreen> {
  // Direction the rolling digits should roll on the next tick: +1 = up (price
  // rose), -1 = down. Derived from successive USD rates via [_onPriceTick] —
  // mirroring the home header so the full-screen price rolls identically.
  LivePriceController? _priceController;
  double? _prevUsd;
  int _rollDirection = 1;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(kLandscapeOrientations);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<LivePriceController>();
    if (!identical(controller, _priceController)) {
      _priceController?.removeListener(_onPriceTick);
      _priceController = controller;
      _prevUsd = controller.rates.usd;
      controller.addListener(_onPriceTick);
    }
  }

  void _onPriceTick() {
    final usd = _priceController?.rates.usd;
    if (usd == null || usd <= 0) return;
    final prev = _prevUsd;
    _prevUsd = usd;
    if (prev == null || prev == usd) return;
    final direction = usd > prev ? 1 : -1;
    if (direction != _rollDirection && mounted) {
      setState(() => _rollDirection = direction);
    }
  }

  @override
  void dispose() {
    _priceController?.removeListener(_onPriceTick);
    // Leave the system UI mode alone — the home screen re-asserts the correct
    // mode for its orientation in didPopNext. Setting edgeToEdge here would
    // flash the system bars back on when returning to a landscape home screen.
    SystemChrome.setPreferredOrientations(kDefaultOrientations);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentPrice = context.select<LivePriceController, double?>(
      (c) => c.rates.forCurrency(widget.currency),
    );

    // SafeArea insets only the side with the camera cutout, which would shove
    // the centered price off true center. Mirror the larger inset onto both
    // sides (and top/bottom) so the safe box stays symmetric and the price
    // sits dead-center on the physical screen.
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final hInset =
        math.max(viewPadding.left, viewPadding.right) + AppSpacing.lg;
    final vInset = math.max(viewPadding.top, viewPadding.bottom);

    return Scaffold(
      backgroundColor: cs.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection();
          Navigator.of(context).maybePop();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hInset, vertical: vInset),
          // SizedBox.expand gives FittedBox a bounded box that fills the whole
          // (safe, symmetrically padded) screen. BoxFit.contain then scales the
          // price *up* to fill it — and re-fits on every tick, so the size
          // shrinks/grows automatically as digits come and go. Without the
          // expanding box, Center would hand FittedBox unbounded constraints
          // and the text would just render at its intrinsic size.
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              child: RollingNumber(
                text: currentPrice != null
                    ? formatFiat(currentPrice, widget.currency).tight
                    : '',
                direction: _rollDirection,
                style: AppTypography.display.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
