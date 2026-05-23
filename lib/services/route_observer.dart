import 'package:flutter/material.dart';

/// Global route observer. Widgets that need to react when the route they live
/// on becomes visible again (e.g. the mempool block strip re-centering its
/// divider after returning from Settings) subscribe via [RouteAware].
///
/// Lives in services/ rather than main.dart so other code can subscribe
/// without importing the app's entry point.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
