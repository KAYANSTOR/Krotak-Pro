import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/screens/help_center_screen.dart';
import 'package:net_app/ui/widgets/async_views.dart';

void main() {
  testWidgets('HelpCenterScreen renders current offline topics', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();

    // App bar + video-parity groups (chip filter + section header share the same label)
    expect(find.textContaining('مركز المساعدة'), findsWidgets);
    expect(find.text('البدء والصلاحيات'), findsWidgets);
    expect(find.text('الرسائل والمعالجة'), findsWidgets);
    expect(find.text('المخزون والكروت'), findsWidgets);
  });

  testWidgets('HelpCenterScreen supports expansion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();

    // Expand the first item card in the list (ListTile / ExpansionTile style)
    final item = find.text('تهيئة التشغيل عند أول فتح');
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('ورقة سفلية'),
      findsWidgets,
    );
  });

  testWidgets('AsyncErrorView shows retry', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: AsyncErrorView(message: 'فشل', onRetry: () => tapped = true),
    ));
    await tester.tap(find.text('إعادة المحاولة'));
    expect(tapped, isTrue);
  });

  testWidgets('AsyncEmptyView optional action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: AsyncEmptyView(
        message: 'فارغ',
        actionLabel: 'إضافة',
        onAction: () => tapped = true,
      ),
    ));
    await tester.tap(find.text('إضافة'));
    expect(tapped, isTrue);
  });
}
