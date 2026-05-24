import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../theme/theme.dart';

/// Full-screen square-crop step shown between the gallery pick and the
/// downscale/encode pipeline. Pops the cropped JPEG/PNG bytes on confirm,
/// or null if the user backs out.
class CropStackImageScreen extends StatefulWidget {
  const CropStackImageScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CropStackImageScreen> createState() => _CropStackImageScreenState();
}

class _CropStackImageScreenState extends State<CropStackImageScreen> {
  final _controller = CropController();
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(
          color: cs.onSurfaceVariant,
          onPressed: () {
            AppHaptics.light();
            Navigator.of(context).maybePop<Uint8List?>(null);
          },
        ),
        centerTitle: true,
        title: Text(
          l10n.stackImageCropTitle,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _processing
                ? null
                : () {
                    AppHaptics.light();
                    setState(() => _processing = true);
                    _controller.crop();
                  },
            child: Text(
              l10n.stackImageCropConfirm,
              style: AppTypography.body.copyWith(
                color: context.palette.bitcoinOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Crop(
          image: widget.imageBytes,
          controller: _controller,
          withCircleUi: true,
          interactive: true,
          baseColor: cs.surfaceContainerLow,
          maskColor: Colors.black.withValues(alpha: 0.5),
          cornerDotBuilder: (size, edgeAlignment) => DotControl(
            color: context.palette.bitcoinOrange,
          ),
          onCropped: (result) {
            if (!mounted) return;
            switch (result) {
              case CropSuccess(:final croppedImage):
                Navigator.of(context).pop<Uint8List?>(croppedImage);
              case CropFailure():
                setState(() => _processing = false);
            }
          },
        ),
      ),
    );
  }
}
