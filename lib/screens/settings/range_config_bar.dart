import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';

// Stable, sorted candidate lists for each configurable slot — same sources the
// home-screen range bar uses, so the two stay in lockstep.
final List<BtcRange> _daysRanges = btcRangeDays;
final List<BtcRange> _weeksRanges = btcRangeWeeks;
final List<BtcRange> _monthsRanges = btcRangeMonths;
final List<BtcRange> _yearsRanges = btcRangeYears;

/// Settings row that matches [SettingsSegmentedTile] (label on the left,
/// control on the right) but whose control is a non-interactive twin of the
/// home screen's range bar: the same recessed grey track with the four
/// user-customizable slots (days, weeks, months, years) — without the sliding
/// selection pill, drag, or swipe gestures.
///
/// Tapping one of the four slots opens a picker to choose which range that
/// position shows; the choice writes the matching overflow slot on
/// [AppStateNotifier], which is exactly what the home bar reads back.
class SettingsRangesTile extends StatelessWidget {
  const SettingsRangesTile({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Text(
            label,
            style: AppTypography.body.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
          const _RangeConfigBar(),
        ],
      ),
    );
  }
}

// The grey range track that sits on the right side of the Ranges row. Sizes to
// its content (unlike the full-width home bar) so it aligns to the right edge
// like the Height/Scale segmented controls.
class _RangeConfigBar extends StatelessWidget {
  const _RangeConfigBar();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Match the track of the Height/Scale segmented controls above (see
    // _Segments in settings_widgets.dart) rather than the home bar's recessed
    // grey, so all three rows read as one set.
    final trackFill = cs.surfaceContainerLow;

    final daysSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.daysOverflowQuickRange,
    );
    final weeksSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.weeksOverflowQuickRange,
    );
    final monthsSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.monthsOverflowQuickRange,
    );
    final yearsSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.overflowQuickRange,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: trackFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConfigSlot(
              label: _btcRangeLabel(context, daysSlot),
              onTap: () => _pick(
                context,
                ranges: _daysRanges,
                keyPrefix: 'cfgDaysSlot',
                getCurrent: (a) => a.daysOverflowQuickRange,
                setCurrent: (a, v) => a.setDaysOverflowQuickRange(v),
                longLabel: _daysLongLabel,
              ),
            ),
            _ConfigSlot(
              label: _btcRangeLabel(context, weeksSlot),
              onTap: () => _pick(
                context,
                ranges: _weeksRanges,
                keyPrefix: 'cfgWeeksSlot',
                getCurrent: (a) => a.weeksOverflowQuickRange,
                setCurrent: (a, v) => a.setWeeksOverflowQuickRange(v),
                longLabel: _weeksLongLabel,
              ),
            ),
            _ConfigSlot(
              label: _btcRangeLabel(context, monthsSlot),
              onTap: () => _pick(
                context,
                ranges: _monthsRanges,
                keyPrefix: 'cfgMonthsSlot',
                getCurrent: (a) => a.monthsOverflowQuickRange,
                setCurrent: (a, v) => a.setMonthsOverflowQuickRange(v),
                longLabel: _monthsLongLabel,
              ),
            ),
            _ConfigSlot(
              label: _btcRangeLabel(context, yearsSlot),
              onTap: () => _pick(
                context,
                ranges: _yearsRanges,
                keyPrefix: 'cfgYearsSlot',
                getCurrent: (a) => a.overflowQuickRange,
                setCurrent: (a, v) => a.setOverflowQuickRange(v),
                longLabel: _yearsLongLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Shows the same radio-group picker the home bar uses for an overflow slot,
  // writing the chosen range back to [setCurrent]. Does not change the active
  // home-screen range — it only configures which range this slot displays.
  Future<void> _pick(
    BuildContext context, {
    required List<BtcRange> ranges,
    required String keyPrefix,
    required BtcRange Function(AppStateNotifier) getCurrent,
    required void Function(AppStateNotifier, BtcRange) setCurrent,
    required String Function(BuildContext, BtcRange) longLabel,
  }) async {
    final app = context.read<AppStateNotifier>();
    final current = getCurrent(app);
    final picked = await showDialog<BtcRange>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return Dialog(
          elevation: 24,
          shadowColor: Colors.black,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.rangePickerLongTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in ranges.asMap().entries) ...[
                          if (entry.key > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Theme.of(ctx).colorScheme.outlineVariant,
                            ),
                          _BtcRangeRow(
                            key: ValueKey('$keyPrefix-${entry.value.name}'),
                            label: longLabel(ctx, entry.value),
                            selected: entry.value == current,
                            onTap: () => Navigator.of(ctx).pop(entry.value),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setCurrent(app, picked);
      // If the home bar's pill was sitting on this slot (the active range equals
      // the slot's previous value), follow it to the new range so the pill stays
      // visible on that slot instead of vanishing when the user returns home.
      if (app.btcRange == current) {
        app.setBtcRange(picked);
      }
    }
  }
}

// One slot on the config bar: a content-sized, tappable label styled like the
// unselected segments of the Height/Scale controls. No selection styling —
// every slot reads the same, since this bar configures what each position
// shows rather than which is active.
class _ConfigSlot extends StatelessWidget {
  const _ConfigSlot({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: AppTypography.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

String _btcRangeLabel(BuildContext context, BtcRange r) {
  final l10n = AppLocalizations.of(context);
  return switch (r) {
    BtcRange.d1 => l10n.rangePill1D,
    BtcRange.d2 => l10n.rangePill2D,
    BtcRange.d3 => l10n.rangePill3D,
    BtcRange.d4 => l10n.rangePill4D,
    BtcRange.d5 => l10n.rangePill5D,
    BtcRange.d6 => l10n.rangePill6D,
    BtcRange.d7 => l10n.rangePill7D,
    BtcRange.w1 => l10n.rangePill1W,
    BtcRange.w2 => l10n.rangePill2W,
    BtcRange.w3 => l10n.rangePill3W,
    BtcRange.w4 => l10n.rangePill4W,
    BtcRange.m1 => l10n.rangePill1M,
    BtcRange.m2 => l10n.rangePill2M,
    BtcRange.m3 => l10n.rangePill3M,
    BtcRange.m4 => l10n.rangePill4M,
    BtcRange.m5 => l10n.rangePill5M,
    BtcRange.m6 => l10n.rangePill6M,
    BtcRange.m7 => l10n.rangePill7M,
    BtcRange.m8 => l10n.rangePill8M,
    BtcRange.m9 => l10n.rangePill9M,
    BtcRange.m10 => l10n.rangePill10M,
    BtcRange.m11 => l10n.rangePill11M,
    BtcRange.m12 => l10n.rangePill12M,
    BtcRange.y1 => l10n.rangePill1Y,
    BtcRange.y2 => l10n.rangePill2Y,
    BtcRange.y3 => l10n.rangePill3Y,
    BtcRange.y4 => l10n.rangePill4Y,
    BtcRange.y5 => l10n.rangePill5Y,
    BtcRange.y6 => l10n.rangePill6Y,
    BtcRange.y7 => l10n.rangePill7Y,
    BtcRange.y8 => l10n.rangePill8Y,
    BtcRange.y9 => l10n.rangePill9Y,
    BtcRange.y10 => l10n.rangePill10Y,
    BtcRange.y11 => l10n.rangePill11Y,
    BtcRange.y12 => l10n.rangePill12Y,
    BtcRange.y13 => l10n.rangePill13Y,
    BtcRange.y14 => l10n.rangePill14Y,
    BtcRange.y15 => l10n.rangePill15Y,
    BtcRange.all => l10n.rangePillAll,
  };
}

class _BtcRangeRow extends StatelessWidget {
  const _BtcRangeRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final radius = BorderRadius.circular(AppSpacing.radius);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? p.bitcoinOrange : cs.outline,
                    width: 2,
                  ),
                  color: selected ? p.bitcoinOrange : Colors.transparent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.title.copyWith(
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _daysLongLabel(BuildContext context, BtcRange r) {
  final d = r.days;
  if (d == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerDaysFull(d);
}

String _weeksLongLabel(BuildContext context, BtcRange r) {
  final w = r.weeks;
  if (w == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerWeeksFull(w);
}

String _monthsLongLabel(BuildContext context, BtcRange r) {
  final months = r.months;
  if (months == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerMonthsFull(months);
}

String _yearsLongLabel(BuildContext context, BtcRange r) {
  final years = r.years;
  if (years == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerYearsFull(years);
}
