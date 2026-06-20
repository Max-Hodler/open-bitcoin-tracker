import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/reorder_row.dart';
import '../../widgets/scroll_hairline.dart';

class ReorderStacksScreen extends StatelessWidget {
  const ReorderStacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final stacks = app.stacks;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final hPad = isLandscape ? 64.0 : AppSpacing.md;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56 + (hPad - AppSpacing.md),
        leading: Padding(
          padding: EdgeInsets.only(left: hPad - AppSpacing.md),
          child: BackButton(color: cs.onSurfaceVariant),
        ),
        centerTitle: true,
        titleSpacing: hPad,
        title: Text(
          l10n.settingsReorderStacks,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ScrollHairline(
              child: ReorderableListView.builder(
                padding: EdgeInsets.fromLTRB(
                  hPad,
                  AppSpacing.lg,
                  hPad,
                  AppSpacing.xl * 2,
                ),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) =>
                    ReorderRowDragProxy(animation: animation, child: child),
                onReorderStart: (_) => AppHaptics.medium(),
                onReorder: (oldIndex, newIndex) {
                  AppHaptics.medium();
                  app.reorderStacks(oldIndex, newIndex);
                },
                itemCount: stacks.length,
                itemBuilder: (context, index) {
                  final s = stacks[index];
                  return Padding(
                    key: ValueKey(s.id),
                    padding: EdgeInsets.only(
                      bottom: index == stacks.length - 1 ? 0 : AppSpacing.xs,
                    ),
                    child: ReorderRow(
                      index: index,
                      label: s.name,
                      imageData: s.imageData,
                      colorKey: s.colorKey,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

