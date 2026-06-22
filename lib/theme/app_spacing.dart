import 'package:flutter/widgets.dart';

class AppSpacing {
  AppSpacing._();

  static const double xs = 6.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;

  static const double radius = 12.0;
  static const double radiusLarge = 16.0;

  static const double stackCardHeight = 64.0;

  // Inset shared by the tappable menu/dialog rows (auth-mode picker, lock
  // timeout list, the portfolio toggle). The 14px vertical sits intentionally
  // between [sm] and [md] to give these rows a comfortable touch height.
  static const EdgeInsets menuRowPadding =
      EdgeInsets.symmetric(horizontal: sm, vertical: 14);

  // Shared expand/collapse animation cadence used by expandable cards,
  // the header section reveal, and the price ticker crossfade.
  static const Duration motionDuration = Duration(milliseconds: 260);
}
