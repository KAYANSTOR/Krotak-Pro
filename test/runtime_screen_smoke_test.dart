import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/home_shell.dart';
import 'package:net_app/ui/main_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot and render all primary screens without runtime errors', (tester) async {
    final container = await AppContainer.bootstrap(
      templates: const [
        TransferTemplate(
          id: 'tpl-test',
          name: 'اختبار',
          pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
          isActive: true,
        ),
      ],
    );

    addTearDown(container.dispose);

    await tester.pumpWidget(NetApp(container: container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Exercise every primary tab. HomeShell keeps all five pages in an
    // IndexedStack, but explicit selection also verifies navigation state.
    final navLabels = <String>['التقارير', 'العروض', 'الحسابات', 'الكروت', 'لوحة التحكم'];
    for (final label in navLabels) {
      final finder = find.text(label).first;
      expect(finder, findsWidgets, reason: 'Primary navigation label missing: $label');
      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'Runtime exception while opening $label');
    }

    // The failing application installs ErrorWidget.builder; a real Flutter
    // exception would still be captured by takeException above.
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
