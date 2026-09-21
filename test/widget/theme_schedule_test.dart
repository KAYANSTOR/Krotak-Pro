import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:krotak_pro/ui/theme/net_theme_schedule.dart';
import 'package:krotak_pro/ui/widgets/dashboard/theme_mode_sheet.dart';

void main() {
  group('NetThemeSchedule', () {
    test('parses stored values with backward compatibility', () {
      expect(NetThemeSchedule.parse('light'), NetThemeMode.light);
      expect(NetThemeSchedule.parse('dark'), NetThemeMode.dark);
      expect(NetThemeSchedule.parse('auto'), NetThemeMode.auto);
      // قيمة `system` القديمة تُقرأ كوضع نهاري ثابت.
      expect(NetThemeSchedule.parse('system'), NetThemeMode.light);
      expect(NetThemeSchedule.parse(null), NetThemeMode.light);
      expect(NetThemeSchedule.parse('garbage'), NetThemeMode.light);
    });

    test('encodes back to stored values', () {
      expect(NetThemeSchedule.encode(NetThemeMode.light), 'light');
      expect(NetThemeSchedule.encode(NetThemeMode.dark), 'dark');
      expect(NetThemeSchedule.encode(NetThemeMode.auto), 'auto');
    });

    test('dark window is 19:00 → 07:00', () {
      expect(
        NetThemeSchedule.isDarkTimeNow(DateTime(2026, 9, 18, 19)),
        isTrue,
        reason: '7 مساءً تبدأ نافذة الداكن',
      );
      expect(
        NetThemeSchedule.isDarkTimeNow(DateTime(2026, 9, 18, 23)),
        isTrue,
      );
      expect(
        NetThemeSchedule.isDarkTimeNow(DateTime(2026, 9, 18, 3)),
        isTrue,
      );
      expect(
        NetThemeSchedule.isDarkTimeNow(DateTime(2026, 9, 18, 6, 59)),
        isTrue,
      );
      expect(
        NetThemeSchedule.isDarkTimeNow(DateTime(2026, 9, 18, 7)),
        isFalse,
        reason: '7 صباحًا تنتهي نافذة الداكن',
      );
      expect(
        NetThemeSchedule.isDarkTimeNow(DateTime(2026, 9, 18, 12)),
        isFalse,
      );
      expect(
        NetThemeSchedule.isDarkTimeNow(DateTime(2026, 9, 18, 18, 59)),
        isFalse,
      );
    });

    test('resolve maps each mode correctly at a fixed instant', () {
      final morning = DateTime(2026, 9, 18, 9);
      final night = DateTime(2026, 9, 18, 21);

      expect(NetThemeSchedule.resolve(NetThemeMode.light, night), ThemeMode.light);
      expect(NetThemeSchedule.resolve(NetThemeMode.dark, morning), ThemeMode.dark);
      expect(NetThemeSchedule.resolve(NetThemeMode.auto, morning), ThemeMode.light);
      expect(NetThemeSchedule.resolve(NetThemeMode.auto, night), ThemeMode.dark);
    });
  });

  group('ThemeModeSheet', () {
    Future<NetThemeMode?> pumpAndPick(
      WidgetTester tester, {
      required NetThemeMode current,
      String? tapLabel,
    }) async {
      NetThemeMode? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      picked = await ThemeModeSheet.show(context, current);
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('اختيار المظهر'), findsOneWidget);
      expect(find.text('نهاري'), findsOneWidget);
      expect(find.text('ليلي'), findsOneWidget);
      expect(find.text('تلقائي'), findsOneWidget);

      if (tapLabel != null) {
        await tester.tap(find.text(tapLabel));
        await tester.pumpAndSettle();
      }
      return picked;
    }

    testWidgets('renders three options and pops with the picked mode', (
      tester,
    ) async {
      final picked = await pumpAndPick(tester, current: NetThemeMode.light, tapLabel: 'تلقائي');
      expect(picked, NetThemeMode.auto);
    });

    testWidgets('closing without selection returns null', (tester) async {
      final picked = await pumpAndPick(tester, current: NetThemeMode.dark);
      expect(picked, isNull);
    });
  });
}
