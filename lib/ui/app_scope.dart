import 'package:flutter/widgets.dart';

import '../application/app_container.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.container,
    required super.child,
  });

  final AppContainer container;

  static AppContainer of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.container;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.container != container;
}
