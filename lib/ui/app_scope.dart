import 'package:flutter/widgets.dart';

import '../application/app_container.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.container,
    required super.child,
  });

  final AppContainer container;

  // Defensive fallback for routes/sheets accidentally built from a context
  // outside the AppScope subtree. The normal path remains the inherited scope.
  static AppContainer? _fallbackContainer;

  static void register(AppContainer container) {
    _fallbackContainer = container;
  }

  static void unregister(AppContainer container) {
    if (identical(_fallbackContainer, container)) {
      _fallbackContainer = null;
    }
  }

  static AppContainer of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope != null) return scope.container;

    final fallback = _fallbackContainer;
    if (fallback != null) return fallback;

    throw FlutterError(
      'AppScope is not available for this BuildContext. '
      'Ensure the widget is mounted below NetApp/AppScope.',
    );
  }

  static AppContainer? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    return scope?.container ?? _fallbackContainer;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.container != container;
}
