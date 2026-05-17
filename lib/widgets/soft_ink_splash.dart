import 'dart:math' as math;

import 'package:flutter/material.dart';

// A radial ink splash with a soft (feathered) outer edge, modeled on the
// Google Calculator press feedback. Standard InkRipple paints a solid disc
// with a hard outer boundary; here the disc's alpha falls off via a radial
// gradient so the ring fades into the surface instead of clipping.

const Duration _kRadiusDuration = Duration(milliseconds: 350);
const Duration _kFadeInDuration = Duration(milliseconds: 75);
const Duration _kFadeOutDuration = Duration(milliseconds: 280);

class SoftInkSplash extends InteractiveInkFeature {
  SoftInkSplash({
    required super.controller,
    required super.referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    required double targetRadius,
    BorderRadius? borderRadius,
    super.onRemoved,
  })  : _position = position,
        _borderRadius = borderRadius ?? BorderRadius.zero,
        _textDirection = textDirection,
        super(color: color) {
    _radiusController = AnimationController(
      duration: _kRadiusDuration,
      vsync: controller.vsync,
    )
      ..addListener(controller.markNeedsPaint)
      ..forward();
    _radius = _radiusController.drive(
      Tween<double>(begin: 0, end: targetRadius)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    );

    final int peakAlpha = (color.a * 255.0).round().clamp(0, 255);
    _fadeInController = AnimationController(
      duration: _kFadeInDuration,
      vsync: controller.vsync,
    )
      ..addListener(controller.markNeedsPaint)
      ..forward();
    _fadeIn = _fadeInController.drive(IntTween(begin: 0, end: peakAlpha));

    _fadeOutController = AnimationController(
      duration: _kFadeOutDuration,
      vsync: controller.vsync,
    )
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_handleFadeOutStatus);
    _fadeOut = _fadeOutController.drive(
      IntTween(begin: peakAlpha, end: 0)
          .chain(CurveTween(curve: Curves.easeOut)),
    );

    controller.addInkFeature(this);
  }

  final Offset _position;
  final BorderRadius _borderRadius;
  final TextDirection _textDirection;

  late final AnimationController _radiusController;
  late final Animation<double> _radius;
  late final AnimationController _fadeInController;
  late final Animation<int> _fadeIn;
  late final AnimationController _fadeOutController;
  late final Animation<int> _fadeOut;

  static const InteractiveInkFeatureFactory splashFactory = _SoftInkSplashFactory();

  bool _fadingOut = false;

  void _handleFadeOutStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      dispose();
    }
  }

  @override
  void confirm() {
    _fadingOut = true;
    _fadeOutController.forward();
  }

  @override
  void cancel() {
    _fadingOut = true;
    _fadeInController.stop();
    final double fadeOutValue = 1.0 - _fadeInController.value;
    _fadeOutController.value = fadeOutValue;
    _fadeOutController.forward();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _fadeInController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final int alpha = _fadingOut ? _fadeOut.value : _fadeIn.value;
    if (alpha == 0) return;

    final double radius = _radius.value;
    if (radius <= 0) return;

    final Color baseColor = color.withAlpha(alpha);
    // The gradient: center is solid baseColor, fading to fully transparent
    // exactly at the outer edge. The 0.65 inner stop keeps the inside
    // visibly colored before the soft falloff begins.
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          baseColor,
          baseColor,
          baseColor.withAlpha(0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: _position, radius: radius));

    final Offset? originOffset = MatrixUtils.getAsTranslation(transform);
    canvas.save();
    if (originOffset == null) {
      canvas.transform(transform.storage);
    } else {
      canvas.translate(originOffset.dx, originOffset.dy);
    }

    final Rect clipRect = Offset.zero & referenceBox.size;
    if (_borderRadius != BorderRadius.zero) {
      canvas.clipRRect(
        _borderRadius.resolve(_textDirection).toRRect(clipRect),
      );
    } else {
      canvas.clipRect(clipRect);
    }
    canvas.drawCircle(_position, radius, paint);
    canvas.restore();
  }
}

class _SoftInkSplashFactory extends InteractiveInkFeatureFactory {
  const _SoftInkSplashFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    final Rect bounds = rectCallback != null
        ? rectCallback()
        : Offset.zero & referenceBox.size;
    final double targetRadius = radius ?? _defaultTargetRadius(bounds, position);
    return SoftInkSplash(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      targetRadius: targetRadius,
      borderRadius: borderRadius,
      onRemoved: onRemoved,
    );
  }

  static double _defaultTargetRadius(Rect bounds, Offset position) {
    final double d1 = (position - bounds.topLeft).distance;
    final double d2 = (position - bounds.topRight).distance;
    final double d3 = (position - bounds.bottomLeft).distance;
    final double d4 = (position - bounds.bottomRight).distance;
    // 1.15× the farthest corner so the soft outer falloff has room to fade
    // past the button edge instead of clipping mid-fade.
    return math.max(math.max(d1, d2), math.max(d3, d4)) * 1.15;
  }
}
