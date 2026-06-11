import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../../widgets/expandable_card.dart';
import 'hashrate_card_content.dart';

/// Network hashrate card on the home screen. Polls the mempool.space hashrate
/// endpoint via [HashrateController] and displays the current EH/s value plus
/// a signed percent change vs the oldest sample in the active window. Tapping
/// the row expands an inline chart and pill bar; tapping again collapses it.
/// Until the user has ever expanded the card the row's range is the 3d
/// window; once they have, the row keeps reading whichever pill is currently
/// selected (e.g. `+14.2% 1Y`) — the selection persists across collapse.
class HashrateCard extends StatefulWidget {
  const HashrateCard({super.key});

  @override
  State<HashrateCard> createState() => _HashrateCardState();
}

class _HashrateCardState extends State<HashrateCard>
    with
        SingleTickerProviderStateMixin,
        ExpandableCardStateMixin<HashrateCard> {
  HashrateController? _controller;

  HashrateRange _chartRange = HashrateRange.y1;
  final ValueNotifier<HashratePoint?> _hover = ValueNotifier(null);
  int _lastHoverHapticMs = 0;

  HashrateRange? _displayedRowRange;
  HashrateSnapshot? _displayedRowSnapshot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = context.read<HashrateController>()..addSubscriber();
    _controller = controller;
    _chartRange = context.read<AppStateNotifier>().hashrateRange;
    scheduleMicrotask(() {
      if (!mounted) return;
      controller.setActiveRange(_chartRange);
    });
  }

  @override
  void dispose() {
    _hover.dispose();
    _controller?.removeSubscriber();
    super.dispose();
  }

  void _toggleExpanded() {
    AppHaptics.selection();
    setExpanded(!isExpanded);
    _hover.value = null;
    _controller?.setActiveRange(_chartRange);
  }

  void _onRangeChanged(HashrateRange range) {
    if (range == _chartRange) return;
    setState(() => _chartRange = range);
    _hover.value = null;
    _controller?.setActiveRange(range);
    context.read<AppStateNotifier>().setHashrateRange(range);
  }

  void _onChartHover(HashratePoint? point) {
    if (_hover.value?.timestampMs == point?.timestampMs) return;
    _hover.value = point;
    if (point == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastHoverHapticMs < 90) return;
    _lastHoverHapticMs = now;
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final targetRowRange = _chartRange;
    final chartRange = _chartRange;
    final vm = context.select<HashrateController, HashrateCardViewModel>(
      (c) => HashrateCardViewModel(
        targetRowSnapshot: c.snapshotFor(targetRowRange),
        targetRowFailed: c.didFail(targetRowRange),
        chartSnapshot: c.snapshotFor(chartRange),
        chartLoading: c.isLoading(chartRange),
        chartFailed: c.didFail(chartRange),
      ),
    );

    if (vm.targetRowSnapshot != null) {
      _displayedRowRange = targetRowRange;
      _displayedRowSnapshot = vm.targetRowSnapshot;
    }
    final rowSnapshot = _displayedRowSnapshot;
    final rowRange = _displayedRowRange ?? targetRowRange;

    final fullyFailed = vm.targetRowFailed && rowSnapshot == null;

    final Widget body;
    if (fullyFailed) {
      body = HashrateErrorBody(
        onRetry: () =>
            context.read<HashrateController>().refetchRange(targetRowRange),
      );
    } else if (rowSnapshot == null) {
      body = const HashrateLoadingBody();
    } else {
      body = HashrateCardContent(
        snapshot: rowSnapshot,
        rowRange: rowRange,
        expansionMounted: expansionMounted,
        expandAnimation: expandCurve,
        chartRange: chartRange,
        chartSnapshot: vm.chartSnapshot,
        chartLoading: vm.chartLoading,
        chartFailed: vm.chartFailed,
        hover: _hover,
        onChartHover: _onChartHover,
        onTapRow: _toggleExpanded,
        onRangeChanged: _onRangeChanged,
        onRetryChart: () =>
            context.read<HashrateController>().refetchRange(chartRange),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: body,
    );
  }
}
