import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/stack_avatar_color.dart';
import '../theme/theme.dart';

/// Circular avatar for a stack: shows the picked image when [imageData] is
/// set, otherwise a tinted circle with the name's first grapheme. The tint
/// is bitcoinOrange by default but can be overridden via [colorKey] (see
/// [StackAvatarColor.palette]). Tapping triggers [onTap].
class StackAvatar extends StatelessWidget {
  const StackAvatar({
    super.key,
    required this.name,
    this.imageData,
    this.colorKey,
    this.size = 48,
    this.onTap,
  });

  final String name;
  // Raw base64 JPEG bytes, or null to render the initial-letter fallback.
  final String? imageData;
  // Palette key from [StackAvatarColor]. Null → theme's bitcoinOrange.
  final String? colorKey;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final orange =
        StackAvatarColor.resolve(colorKey) ?? context.palette.bitcoinOrange;
    final Widget face;
    if (imageData != null) {
      face = ClipOval(
        child: Image.memory(
          base64Decode(imageData!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } else {
      face = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: orange.withValues(alpha: 0.18),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _initial(name),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: orange,
                fontWeight: FontWeight.w600,
                fontSize: size * 0.45,
                height: 1,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: face,
        ),
      ),
    );
  }
}

String _initial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final first = trimmed.characters.first;
  return first.toUpperCase();
}
