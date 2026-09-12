import 'package:flutter_test/flutter_test.dart';

// Full widget tests against a real `AppContainer` (Drift over
// `NativeDatabase.memory()`) now live in
// `test/widget/app_container_screens_test.dart`, via the new
// `AppContainer.forTesting(...)` factory. This file is kept as a trivial
// smoke placeholder so a stray `flutter test test/widget_test.dart` still
// resolves to something.
void main() {
  test('placeholder — see test/widget/app_container_screens_test.dart', () {
    expect(1 + 1, 2);
  });
}
