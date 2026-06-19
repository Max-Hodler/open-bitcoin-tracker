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
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(kLandscapeOrientations);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: cs.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection();
          Navigator.of(context).maybePop();
        },
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  currentPrice != null
                      ? formatFiat(currentPrice, widget.currency).tight
                      : '',
                  maxLines: 1,
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
      ),
    );
  }
}
