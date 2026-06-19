import 'package:flutter/material.dart';

/// SafeArea variant for modal bottom sheets.
///
/// A plain [SafeArea] insets the left and right edges by each side's system
/// padding independently. In landscape the display cutout sits on one side
/// only, so its (large) inset pads that edge while the opposite edge gets
/// almost nothing — the sheet content ends up shoved sideways with a big gap
/// on the cutout side.
///
/// This widget keeps content centred by padding both horizontal edges with the
/// *larger* of the two insets, and preserves the bottom inset (gesture nav bar)
/// while ignoring the top (the sheet never reaches the top of the screen).
///
/// In landscape the horizontal inset is halved — the cutout/gesture margins eat
/// a lot of width, and the full inset on both edges leaves the sheet feeling
/// over-padded, so we trade a little safe-area for usable content width.
class SheetSafeArea extends StatelessWidget {
  const SheetSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final padding = mq.viewPadding;
    final isLandscape = mq.orientation == Orientation.landscape;
    var horizontal = padding.left > padding.right
        ? padding.left
        : padding.right;
    if (isLandscape) horizontal /= 2;
    return Padding(
      padding: EdgeInsets.only(
        left: horizontal,
        right: horizontal,
        bottom: padding.bottom,
      ),
      child: child,
    );
  }
}
