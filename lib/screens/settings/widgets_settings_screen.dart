import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import 'settings_widgets.dart';

class WidgetsSettingsScreen extends StatelessWidget {
  const WidgetsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    // Only widgets actually shown on home can be reordered here. Stacks is
    // always visible; mempool and hashrate appear only when their toggles are
    // on. Keep each entry's index into the full order so a reorder can be
    // translated back to the unfiltered list (hidden widgets keep their slots).
    final order = app.homeWidgetOrder;
    final visible = <({int fullIndex, HomeWidget widget})>[
      for (var i = 0; i < order.length; i++)
        if (_isWidgetVisible(app, order[i]))
          (fullIndex: i, widget: order[i]),
    ];

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.onSurfaceVariant),
        centerTitle: true,
        title: Text(
          l10n.settingsWidgets,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: ScrollHairline(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl * 2,
          ),
          children: [
            _SectionTitle(l10n.settingsMempoolWidget),
            SettingsGroup(
              children: [
                SettingsToggleTile(
                  label: l10n.settingsMempoolBlocksVisible,
                  value: app.showMempool,
                  enabled: true,
                  onChanged: app.setShowMempool,
                ),
                SettingsToggleTile(
                  label: l10n.settingsMempoolBlocksReverseOrder,
                  value: app.mempoolBlocksReversed,
                  enabled: app.showMempool,
                  onChanged: app.setMempoolBlocksReversed,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle(l10n.settingsHashrateWidget),
            SettingsGroup(
              children: [
                SettingsToggleTile(
                  label: l10n.settingsHashrateVisible,
                  value: app.showHashrate,
                  enabled: true,
                  onChanged: app.setShowHashrate,
                ),
              ],
            ),
            // Reordering only makes sense with at least two visible widgets, so
            // the whole section drops out when mempool and hashrate are both off
            // (leaving just the always-present stacks widget).
            if (visible.length >= 2) ...[
              const SizedBox(height: AppSpacing.lg),
              _SectionTitle(l10n.settingsReorderWidgets),
              // Each row is its own rounded card so it can lift cleanly under the
              // drag proxy; an xs gap separates them. The list shrink-wraps and
              // delegates scrolling to the outer ListView.
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) =>
                    _ReorderRowDragProxy(animation: animation, child: child),
                onReorderStart: (_) => AppHaptics.medium(),
                onReorder: (oldIndex, newIndex) {
                  AppHaptics.medium();
                  // The list only holds the visible widgets, but the state
                  // stores the full order. Map the visible-list indices back to
                  // the full order (keeping Flutter's insertion-slot convention)
                  // so hidden widgets stay pinned in their original positions.
                  final oldFull = visible[oldIndex].fullIndex;
                  final newFull = newIndex >= visible.length
                      ? order.length
                      : visible[newIndex].fullIndex;
                  app.reorderHomeWidgets(oldFull, newFull);
                },
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final w = visible[index].widget;
                  return Padding(
                    key: ValueKey(w.code),
                    padding: EdgeInsets.only(
                      bottom: index == visible.length - 1 ? 0 : AppSpacing.xs,
                    ),
                    child: _ReorderRow(
                      index: index,
                      label: _homeWidgetLabel(l10n, w),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Header rendered above a [SettingsGroup] to name the section. Matches the
/// section headers on the About screen.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        label,
        style: AppTypography.body.copyWith(
          fontSize: 16,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ReorderRow extends StatelessWidget {
  const _ReorderRow({required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Icon(
                  Icons.drag_handle,
                  size: 24,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderRowDragProxy extends StatelessWidget {
  const _ReorderRowDragProxy({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15 * animation.value),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// Mirrors the home screen's visibility rules: stacks always shows, mempool and
// hashrate follow their toggles. Keep in sync with home_screen.dart.
bool _isWidgetVisible(AppStateNotifier app, HomeWidget w) {
  switch (w) {
    case HomeWidget.stacks:
      return true;
    case HomeWidget.mempoolFees:
      return app.showMempool;
    case HomeWidget.networkHashrate:
      return app.showHashrate;
  }
}

String _homeWidgetLabel(AppLocalizations l10n, HomeWidget w) {
  switch (w) {
    case HomeWidget.stacks:
      return l10n.stacksWidgetTitle;
    case HomeWidget.mempoolFees:
      return l10n.mempoolWidgetTitle;
    case HomeWidget.networkHashrate:
      return l10n.hashrateWidgetTitle;
  }
}
