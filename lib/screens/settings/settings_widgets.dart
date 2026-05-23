import 'package:flutter/material.dart';

import '../../services/app_haptics.dart';
import '../../theme/theme.dart';

/// Groups related settings rows into a single rounded card with hairline
/// dividers between them. Any [SettingsPickerTile], [SettingsToggleTile],
/// [SettingsSegmentedTile], [SettingsActionTile] or [SettingsRadioRowTile]
/// rendered inside drops its own background and corner radius so the group
/// owns the surface.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppSpacing.radius);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          color: cs.outlineVariant,
        ));
      }
      rows.add(children[i]);
    }
    return _SettingsGroupScope(
      child: Material(
        color: cs.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

class _SettingsGroupScope extends InheritedWidget {
  const _SettingsGroupScope({required super.child});

  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SettingsGroupScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(_SettingsGroupScope oldWidget) => false;
}

/// Row that opens a sub-screen or picker. Renders a label (and optional
/// secondary value) on the left and [trailingIcon] on the right.
class SettingsPickerTile extends StatelessWidget {
  const SettingsPickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.trailingIcon = Icons.unfold_more,
    this.enabled = true,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData trailingIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = value.isNotEmpty;
    final labelColor = enabled ? cs.onSurface : cs.onSurfaceVariant;
    final grouped = _SettingsGroupScope.of(context);
    final radius = grouped ? null : BorderRadius.circular(AppSpacing.radius);
    return Material(
      color: grouped ? Colors.transparent : cs.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: enabled
            ? () {
                AppHaptics.selection();
                onTap();
              }
            : null,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: hasValue
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: AppTypography.body.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value,
                            style: AppTypography.body.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        label,
                        style: AppTypography.body.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: labelColor,
                        ),
                      ),
              ),
              Icon(
                trailingIcon,
                size: 24,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row with a switch on the right. Disabled state dims both the label and the
/// switch and uses an outlined thumb so the user can still tell what's "on".
class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final grouped = _SettingsGroupScope.of(context);
    final radius = BorderRadius.circular(AppSpacing.radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: grouped ? Colors.transparent : cs.surface,
        borderRadius: grouped ? null : radius,
      ),
      child: ClipRRect(
        borderRadius: grouped ? BorderRadius.zero : radius,
        child: SwitchListTile(
          tileColor: Colors.transparent,
          title: Text(
            label,
            style: AppTypography.body.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: enabled ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          horizontalTitleGap: AppSpacing.xs,
          value: value,
          onChanged: enabled
              ? (v) {
                  AppHaptics.light();
                  onChanged(v);
                }
              : null,
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled) && states.contains(WidgetState.selected)) {
              return cs.onSurface.withValues(alpha: 0.38);
            }
            return null;
          }),
          thumbIcon: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Icon(
                Icons.check_rounded,
                size: 18,
                color: enabled ? p.bitcoinOrange : cs.onSurface.withValues(alpha: 0.38),
              );
            }
            return null;
          }),
        ),
      ),
    );
  }
}

/// Row with a small segmented control on the right (e.g. Linear / Log).
class SettingsSegmentedTile extends StatelessWidget {
  const SettingsSegmentedTile({
    super.key,
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = _SettingsGroupScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: grouped ? Colors.transparent : cs.surface,
        borderRadius:
            grouped ? null : BorderRadius.circular(AppSpacing.radius),
      ),
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
                  color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ),
            _Segments(
              options: options,
              selectedIndex: selectedIndex,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.options,
    required this.selectedIndex,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trackColor = enabled ? cs.surfaceContainerLow : cs.surfaceContainerLow.withValues(alpha: 0.5);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              _Segment(
                label: options[i],
                selected: i == selectedIndex,
                enabled: enabled,
                onTap: () {
                  if (i == selectedIndex) return;
                  AppHaptics.light();
                  onChanged(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final Color fill;
    final Color textColor;
    if (selected) {
      fill = enabled ? p.bitcoinOrange : cs.onSurface.withValues(alpha: 0.38);
      textColor = Colors.white;
    } else {
      fill = Colors.transparent;
      textColor = enabled ? cs.onSurface : cs.onSurfaceVariant;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single-line tappable row used for destructive actions ("Reset all", "Turn
/// off lock"). No trailing icon, no value, just the label as a button.
class SettingsActionTile extends StatelessWidget {
  const SettingsActionTile({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = _SettingsGroupScope.of(context);
    final radius = grouped ? null : BorderRadius.circular(AppSpacing.radius);
    return Material(
      color: grouped ? Colors.transparent : cs.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.light();
                onTap!();
              },
        borderRadius: radius,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14,
            ),
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Row with a custom radio dot on the right. Used by the Theme screen instead
/// of [RadioListTile] so the row matches the rest of the settings tiles.
class SettingsRadioRowTile<T> extends StatelessWidget {
  const SettingsRadioRowTile({
    super.key,
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final selected = value == groupValue;
    final labelColor = enabled ? cs.onSurface : cs.onSurfaceVariant;
    final grouped = _SettingsGroupScope.of(context);
    final radius = grouped ? null : BorderRadius.circular(AppSpacing.radius);
    return Material(
      color: grouped ? Colors.transparent : cs.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: enabled
            ? () {
                if (selected) return;
                AppHaptics.selection();
                onChanged(value);
              }
            : null,
        borderRadius: radius,
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
                    color: labelColor,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 22,
                color: selected
                    ? (enabled ? p.bitcoinOrange : cs.onSurfaceVariant)
                    : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
