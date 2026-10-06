import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/app_reloader.dart';

void main() {
  test('reload does nothing and reports false when no app is registered', () async {
    expect(AppReloader.isAvailable, isFalse);
    expect(await AppReloader.reload(), isFalse);
  });

  test('reload runs the registered handler and unregister removes it', () async {
    final owner = Object();
    var calls = 0;
    AppReloader.register(owner, () async => calls++);
    expect(AppReloader.isAvailable, isTrue);
    expect(await AppReloader.reload(), isTrue);
    expect(calls, 1);

    AppReloader.unregister(Object()); // مالك آخر: لا يؤثر
    expect(AppReloader.isAvailable, isTrue);
    AppReloader.unregister(owner);
    expect(AppReloader.isAvailable, isFalse);
  });

  test('the notice is delivered exactly once', () {
    AppReloader.setNotice('تمت الاستعادة');
    expect(AppReloader.takeNotice(), 'تمت الاستعادة');
    expect(AppReloader.takeNotice(), isNull);
  });
}
