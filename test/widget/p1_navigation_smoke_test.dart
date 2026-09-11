import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/screens/help_center_screen.dart';
import 'package:net_app/ui/screens/offers_screen.dart';
import 'package:net_app/ui/widgets/async_views.dart';

void main() {
  testWidgets('OffersScreen shows honest empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OffersScreen()));
    expect(find.textContaining('Post-v1'), findsOneWidget);
  });

  testWidgets('HelpCenterScreen lists offline topics', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    expect(find.text('العملاء'), findsOneWidget);
    expect(find.text('الرصيد والتحويل'), findsOneWidget);
  });

  testWidgets('AsyncErrorView shows retry', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncErrorView(message: 'فشل', onRetry: () => tapped = true),
      ),
    );
    await tester.tap(find.text('إعادة المحاولة'));
    expect(tapped, isTrue);
  });

  testWidgets('AsyncEmptyView optional action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncEmptyView(
          message: 'فارغ',
          actionLabel: 'إضافة',
          onAction: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.text('إضافة'));
    expect(tapped, isTrue);
  });
}
