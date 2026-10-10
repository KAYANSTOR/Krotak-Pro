import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate;
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/screens/settings/settings_hub_screen.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';

/// WP-1 — «إدارة الكروت والفئات» كانت بطاقة مكرّرة في الإعدادات (تبويب الكروت
/// الرئيسي رقم 4 في `home_shell.dart` يقوم بالدور نفسه). تُحذف البطاقة ويبقى
/// المسار الوحيد من الشريط السفلي.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'WP-1: بطاقة «إدارة الكروت والفئات» غير موجودة في الإعدادات ولا في البحث',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final container = await AppContainer.bootstrap(
        databaseOverride: database,
        backupDirectoryOverride: Directory('test-backups'),
      );
      addTearDown(() async {
        await container.dispose();
        await database.close();
      });

      await tester.pumpWidget(
        AppScope(
          container: container,
          child: MaterialApp(
            theme: buildKayanLightTheme(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: SettingsHubScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);

      expect(find.text('إدارة الكروت والفئات'), findsNothing);
      expect(find.byIcon(Icons.style_outlined), findsNothing);
      expect(find.textContaining('استيراد الكروت ومراجعة المخزون'), findsNothing);

      // البحث بكلمات الكروت/الفئات/المخزون يجب ألا يعيد البطاقة المحذوفة.
      for (final query in const ['الكروت', 'الفئات', 'المخزون', 'توليد']) {
        await tester.enterText(find.byType(TextField).first, query);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('إدارة الكروت والفئات'), findsNothing,
            reason: 'البطاقة عادت في نتائج البحث عن «$query»');
        expect(find.textContaining('إدارة الكروت'), findsNothing,
            reason: 'نص البطاقة ظاهر في البحث عن «$query»');
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
