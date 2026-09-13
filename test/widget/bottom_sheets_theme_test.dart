import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/theme/kayan_palette.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/dashboard/quick_actions_sheet.dart';

Widget _app({required ThemeMode mode, required Widget child}) {
  return MaterialApp(
    theme: buildKayanLightTheme(),
    darkTheme: buildKayanDarkTheme(),
    themeMode: mode,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('quick actions sheet lists master-plan actions in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        mode: ThemeMode.dark,
        child: QuickActionsSheet(
          onDirectSale: () {},
          onPosAccounts: () {},
          onAddCustomer: () {},
        ),
      ),
    );

    expect(find.text('إجراءات سريعة'), findsOneWidget);
    expect(find.text('البيع المباشر'), findsOneWidget);
    expect(find.text('حسابات نقاط البيع'), findsOneWidget);
    expect(find.text('إضافة عميل'), findsOneWidget);

    late KayanPalette palette;
    await tester.pumpWidget(
      _app(
        mode: ThemeMode.dark,
        child: Builder(
          builder: (context) {
            palette = KayanPalette.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(palette.isDark, isTrue);
    expect(palette.surface.computeLuminance(), lessThan(0.3));
  });
}
