import 'package:flutter/material.dart';

import '../services/app_haptics.dart';
import '../theme/theme.dart';

/// Full-width button with the bitcoin-orange outline style used across the app.
/// Renders [label] text when supplied, otherwise a check icon.
/// Dimmed and tap-blocked when [isValid] is false.
class OrangeOutlineButton extends StatelessWidget {
  const OrangeOutlineButton({
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
            color: AppColors.bitcoinOrangeTint,
            borderRadius: radius,
            border: Border.all(color: p.bitcoinOrange, width: 0.5),
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
                    ? Icon(Icons.check, size: 28, color: p.bitcoinOrange)
                    : icon != null && label != null
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 20, color: p.bitcoinOrange),
                              const SizedBox(width: 8),
                              Text(
                                label!,
                                style: AppTypography.title.copyWith(
                                  color: p.bitcoinOrange,
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
                                color: p.bitcoinOrange,
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
