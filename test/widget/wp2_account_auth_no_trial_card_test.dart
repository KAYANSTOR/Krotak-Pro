import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/ui/screens/account_auth_screen.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';

/// WP-2 (D4) — إزالة بصرية لبطاقة «حساب دائم — بدون فترة تجريبية» من شاشة
/// الحساب في وضع الإنشاء ووضع الدخول، **دون** أي مساس بمنطق `isTrial`
/// أو الجلسة أو الخادم.
void main() {
  Future<void> pumpAuth(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: AccountAuthScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  void expectNoTrialText() {
    expect(find.textContaining('بدون فترة تجريبية'), findsNothing);
    expect(find.textContaining('حساب دائم'), findsNothing);
    expect(find.byIcon(Icons.workspace_premium_rounded), findsNothing);
  }

  testWidgets('WP-2: لا نص تجريبي في وضع «إنشاء حساب»', (tester) async {
    await pumpAuth(tester);
    expect(find.text('إنشاء الحساب والبدء'), findsOneWidget);
    expectNoTrialText();
  });

  testWidgets('WP-2: لا نص تجريبي في وضع «دخول»', (tester) async {
    await pumpAuth(tester);

    final switchLink = find.text('لدي حساب بالفعل — تسجيل الدخول');
    expect(switchLink, findsOneWidget);
    await tester.ensureVisible(switchLink);
    await tester.pump();
    await tester.tap(switchLink, warnIfMissed: false);
    await tester.pump();

    expect(find.text('دخول'), findsWidgets);
    expectNoTrialText();
  });
}
