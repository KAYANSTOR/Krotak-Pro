import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/screens/help_center_screen.dart';
import 'package:net_app/ui/widgets/async_views.dart';

void main() {
  testWidgets('HelpCenterScreen renders current offline topics', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();

    // Group titles present after video-parity rewrite
    expect(find.text('البدء والصلاحيات'), findsOneWidget);
    expect(find.text('الرسائل والمعالجة'), findsOneWidget);

    // Item near top of inventory section
    final cardsTopic = find.text('الفئات والمخزون');
    await tester.scrollUntilVisible(
      cardsTopic,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(cardsTopic, findsWidgets);

    final reports = find.text('التقارير والعمليات');
    await tester.scrollUntilVisible(
      reports,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(reports, findsWidgets);
  });

  testWidgets('HelpCenterScreen supports expansion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();

    final title = find.text('إضافة واستيراد الكروت');
    await tester.scrollUntilVisible(
      title,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(title, findsOneWidget);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.textContaining('سيريال'), findsWidgets);
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
