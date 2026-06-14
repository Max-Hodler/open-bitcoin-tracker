import 'package:flutter/material.dart';

import '../services/app_haptics.dart';
import '../theme/theme.dart';

/// Full-width primary button with the solid bitcoin-orange style used across
/// the app. Renders [label] text when supplied, otherwise a check icon, in
/// white on an orange fill.
/// Dimmed and tap-blocked when [isValid] is false.
class OrangePrimaryButton extends StatelessWidget {
  const OrangePrimaryButton({
    super.key,
    required this.isValid,
    required this.onTap,
    this.label,
    this.icon,
    this.height = 64,
    this.fullWidth = true,
  });

  final bool isValid;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;
  final double height;

  /// When false, the button hugs its content width instead of stretching to
  /// fill the available horizontal space.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(AppSpacing.radius);
    return Opacity(
      opacity: isValid ? 1.0 : 0.4,
      child: SizedBox(
        height: height,
        width: fullWidth ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.bitcoinOrange,
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isValid
                  ? () {
                      AppHaptics.medium();
                      onTap();
                    }
                  : null,
              child: Align(
                widthFactor: fullWidth ? null : 1.0,
                child: label == null && icon == null
                    ? const Icon(Icons.check, size: 28, color: Colors.white)
                    : icon != null && label != null
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 20, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                label!,
                                style: AppTypography.title.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: fullWidth ? 0 : AppSpacing.lg,
                            ),
                            child: Text(
                              label!,
                              style: AppTypography.title.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
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
