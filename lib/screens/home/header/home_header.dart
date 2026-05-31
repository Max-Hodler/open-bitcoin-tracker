import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../data/data.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../widgets/home_buttons.dart';
import '../widgets/retry_button.dart';
import 'area_chart.dart';
import 'current_price.dart';
import 'range_bar.dart';

/// Reports its child's size via [onChange] on every layout pass.
/// Used to track header height without resorting to a GlobalKey on the
/// header itself (which causes duplicate-key errors when the header is
/// rendered in two places for measurement + display).
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, required Widget super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  // ignore: library_private_types_in_public_api
  void updateRenderObject(BuildContext context, _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
    }
  }
}

class PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const PinnedHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: OverflowBox(
        minHeight: 0,
        maxHeight: double.infinity,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(PinnedHeaderDelegate old) =>
      old.height != height || old.child != child;
}

class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.failed,
    required this.showChart,
    required this.currentPrice,
    required this.hover,
    required this.lastFetchedAt,
    required this.range,
    required this.currency,
    required this.selectedCurrencies,
    required this.chartColor,
    required this.rangePct,
    required this.rollDirection,
    required this.onPriceTap,
    required this.onCurrencySwipe,
    required this.chartData,
    required this.chartWindowStartMs,
    required this.chartWindowEndMs,
    required this.allHistoryEmpty,
    required this.usesAllHistory,
    required this.loading,
    required this.onRange,
    required this.onHover,
    required this.onRetry,
    required this.stacksLocked,
    required this.stacksAuthMode,
    this.onOpenSettings,
    this.onOpenConverter,
  });

  final bool failed;
  final bool showChart;
  final double currentPrice;
  final ValueListenable<PricePoint?> hover;
  final DateTime? lastFetchedAt;
  final BtcRange range;
  final Currency currency;
  final List<Currency> selectedCurrencies;
  final Color chartColor;
  final double? rangePct;
  final int rollDirection;
  final VoidCallback onPriceTap;
  final ValueChanged<int> onCurrencySwipe;
  final List<PricePoint> chartData;
  final int chartWindowStartMs;
  final int chartWindowEndMs;
  final bool allHistoryEmpty;
  final bool usesAllHistory;
  final bool loading;
  final ValueChanged<BtcRange> onRange;
  final ValueChanged<PricePoint?> onHover;
  final VoidCallback onRetry;
  final bool stacksLocked;
  final StacksAuthMode stacksAuthMode;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenConverter;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  @override
  Widget build(BuildContext context) {
    final logScale = context.select<AppStateNotifier, bool>((a) => a.logScale);
    final showButtons = widget.onOpenSettings != null;
    final buttonsRow = !showButtons
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.stacksAuthMode != StacksAuthMode.off &&
                  !widget.stacksLocked)
                LockNowButton(
                  onTap: () =>
                      context.read<StacksLockController>().lockNow(),
                ),
              if (widget.onOpenConverter != null)
                ConverterIconButton(onTap: widget.onOpenConverter!),
              OverflowButton(onTap: widget.onOpenSettings!),
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CurrentPrice(
                  price: widget.currentPrice,
                  hover: widget.hover,
                  lastFetchedAt: widget.lastFetchedAt,
                  range: widget.range,
                  currency: widget.currency,
                  selectedCurrencies: widget.selectedCurrencies,
                  rangePct: widget.rangePct,
                  rollDirection: widget.rollDirection,
                  onPriceTap: widget.onPriceTap,
                  onCurrencySwipe: widget.onCurrencySwipe,
                ),
              ),
              ?buttonsRow,
            ],
          ),
        ),
        if (widget.showChart) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 136,
            child: _buildChartArea(context, logScale: logScale),
          ),
          RangeBar(
            range: widget.range,
            rangePct: widget.rangePct,
            chartColor: widget.chartColor,
            onRange: widget.onRange,
          ),
        ],
      ],
    );
  }

  Widget _buildChartArea(BuildContext context, {required bool logScale}) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final loading =
        widget.usesAllHistory ? widget.allHistoryEmpty : widget.loading;
    if (loading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: p.bitcoinOrange,
          ),
        ),
      );
    }
    if (widget.failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).chartErrorTitle,
              style: AppTypography.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ChartRetryButton(onTap: widget.onRetry),
          ],
        ),
      );
    }
    if (widget.chartData.length < 2) {
      return const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: AreaChart(
        key: ValueKey(widget.usesAllHistory ? 'long' : widget.range.name),
        data: widget.chartData,
        windowStartMs: widget.chartWindowStartMs,
        windowEndMs: widget.chartWindowEndMs,
        color: widget.chartColor,
        logScale: logScale,
        rangeKey: widget.range,
        onHover: widget.onHover,
      ),
    );
  }
}
