import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/screens/help_center_screen.dart';
import 'package:net_app/ui/widgets/async_views.dart';

void main() {
  testWidgets('HelpCenterScreen renders current offline topics', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    expect(find.text('التقارير والعمليات'), findsOneWidget);
    expect(find.text('مركز استرداد العمليات والأخطاء'), findsOneWidget);
    expect(find.text('إدارة وتوليد ومخزون الكروت'), findsOneWidget);
  });

  testWidgets('HelpCenterScreen supports expansion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    final title = find.text('إضافة الكروت يدويًا وبالإدخال النصي السريع');
    expect(title, findsOneWidget);
    await tester.tap(title);
    await tester.pump();
    expect(find.textContaining('تسلسل + رمز'), findsOneWidget);
  });

  testWidgets('AsyncErrorView shows retry', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(home: AsyncErrorView(message: 'فشل', onRetry: () => tapped = true)));
    await tester.tap(find.text('إعادة المحاولة'));
    expect(tapped, isTrue);
  });

  testWidgets('AsyncEmptyView optional action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(home: AsyncEmptyView(message: 'فارغ', actionLabel: 'إضافة', onAction: () => tapped = true)));
    await tester.tap(find.text('إضافة'));
    expect(tapped, isTrue);
  });
}
