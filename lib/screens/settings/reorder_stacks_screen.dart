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

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.onSurfaceVariant),
        centerTitle: true,
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
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

