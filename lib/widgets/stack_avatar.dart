import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/stack_avatar_color.dart';
import '../theme/theme.dart';

// Memo of base64 string → decoded bytes, so rebuilds reuse the same
// Uint8List identity: MemoryImage keys the ImageCache on byte identity, so a
// fresh decode per build means a guaranteed cache miss and a redundant JPEG
// decode. LRU-capped so avatars of deleted stacks don't pin memory forever.
final Map<String, Uint8List> _decodedAvatarBytes = <String, Uint8List>{};
const int _decodedAvatarCap = 32;

Uint8List _decodedBytesFor(String imageData) {
  final cached = _decodedAvatarBytes.remove(imageData);
  if (cached != null) {
    _decodedAvatarBytes[imageData] = cached; // refresh LRU position
    return cached;
  }
  final bytes = base64Decode(imageData);
  if (_decodedAvatarBytes.length >= _decodedAvatarCap) {
    _decodedAvatarBytes.remove(_decodedAvatarBytes.keys.first);
  }
  _decodedAvatarBytes[imageData] = bytes;
  return bytes;
}

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
    this.size = defaultSize,
    this.onTap,
  });

  static const double defaultSize = 48;

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
      // Decode at render resolution: avatars are stored 256×256 but drawn at
      // [size] logical px, so a full-size decode wastes ~4× the bitmap memory.
      final cachePx =
          (size * MediaQuery.devicePixelRatioOf(context)).round();
      face = ClipOval(
        child: Image.memory(
          _decodedBytesFor(imageData!),
          width: size,
          height: size,
          cacheWidth: cachePx,
          cacheHeight: cachePx,
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
