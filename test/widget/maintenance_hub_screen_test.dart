import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, AppSetting;
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/services/local_maintenance_service.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/screens/settings/maintenance_hub_screen.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';

/// WP-3 — شاشة الصيانة الموحّدة: ثلاثة إجراءات فعلية، قفل تزامن، وتصدير CSV
/// حقيقي عبر قناة التخزين (مُحاكاة)، وبلا نص إنجليزي في الواجهة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel('com.kayan.net/storage');

  late List<MethodCall> storageCalls;
  late Future<Object?> Function(MethodCall call) storageHandler;

  Future<AppContainer> boot() async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });
    return container;
  }

  Future<void> pumpHub(WidgetTester tester, AppContainer container) async {
    // شاشة الصيانة أطول من السطح الافتراضي للاختبار: نوسّعه حتى تكون الأزرار
    // مبنية وقابلة للنقر فعلاً (ListView يبني ما يظهر فقط).
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        container: container,
        child: MaterialApp(
          theme: buildKayanLightTheme(),
          home: const MaintenanceHubScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  }

  setUp(() {
    storageCalls = <MethodCall>[];
    storageHandler = (call) async {
      storageCalls.add(call);
      return <String, Object?>{
        'path': 'content://downloads/krotak/Exports/الحركات.csv',
        'uri': 'content://downloads/krotak/Exports/الحركات.csv',
      };
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) => storageHandler(call));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  testWidgets('تعرض ثلاثة أقسام بلا وعد مخالف للتنفيذ', (tester) async {
    final container = await boot();
    await pumpHub(tester, container);

    expect(find.text('تنظيف السجلات'), findsOneWidget);
    expect(find.text('التنظيف العميق'), findsOneWidget);
    expect(find.text('تصدير السجل'), findsOneWidget);
    expect(find.textContaining('تصفير'), findsNothing,
        reason: 'النص القديم «تصفير السجلات» لا يطابق التنفيذ');
    expect(find.text(LocalMaintenanceService.deepCleanSummaryAr), findsOneWidget);
  });

  testWidgets('تصدير CSV: ملف فعلي عبر قناة التخزين + كتابة lastExportAt',
      (tester) async {
    final container = await boot();
    await pumpHub(tester, container);

    await tester.tap(find.text('تصدير ملف CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(storageCalls, hasLength(1));
    final call = storageCalls.single;
    expect(call.method, 'saveToDownloads');
    final args = call.arguments as Map;
    expect(args['mimeType'], 'text/csv');
    expect(args['subfolder'], 'Exports');
    expect((args['fileName'] as String).endsWith('.csv'), isTrue);

    expect(find.textContaining('تم تصدير'), findsOneWidget);

    final saved = await container.settings.find(SettingKeys.lastExportAt);
    expect(saved, isA<Success<AppSetting?>>());
    expect((saved as Success<AppSetting?>).value?.value, isNotEmpty);
  });

  testWidgets('قفل التزامن: كل الأزرار معطّلة أثناء تنفيذ عملية', (tester) async {
    final container = await boot();
    await pumpHub(tester, container);

    // القناة لا تكتمل: نثبّت العملية في وضع «نشط» لفحص القفل.
    storageHandler = (call) => Future<Object?>.delayed(
          const Duration(seconds: 30),
          () => <String, Object?>{'path': 'content://x'},
        );

    await tester.tap(find.text('تصدير ملف CSV'));
    await tester.pump();

    final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
    expect(buttons, isNotEmpty);
    expect(
      buttons.every((button) => button.onPressed == null),
      isTrue,
      reason: 'يجب تعطيل كل الأزرار أثناء تنفيذ عملية واحدة',
    );

    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('تنظيف السجلات: تأكيد ثم نتيجة عربية', (tester) async {
    final container = await boot();
    await pumpHub(tester, container);

    await tester.tap(find.text('تنظيف السجلات المنتهية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('تأكيد تنظيف السجلات'), findsOneWidget);

    await tester.tap(find.text('تنظيف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('حُذفت'), findsOneWidget);
  });

  testWidgets('التنظيف العميق: تأكيد ثم قياس الحجم قبل/بعد', (tester) async {
    final container = await boot();
    await pumpHub(tester, container);

    await tester.tap(find.text('تنفيذ التنظيف العميق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('تأكيد التنظيف العميق'), findsOneWidget);

    await tester.tap(find.text('تنظيف عميق'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('اكتمل التنظيف العميق'), findsOneWidget);
    expect(find.textContaining('حجم قاعدة البيانات'), findsOneWidget);
  });

  testWidgets('لا نص لاتيني في الواجهة (استثناءات موثّقة فقط)', (tester) async {
    final container = await boot();
    await pumpHub(tester, container);

    const allowed = <String>[
      'CSV',
      'Excel',
      'Krotak Pro',
      'REINDEX',
      'VACUUM',
      'ANALYZE',
    ];
    final latin = RegExp('[A-Za-z]');
    for (final element in find.byType(Text).evaluate()) {
      var text = (element.widget as Text).data ?? '';
      for (final term in allowed) {
        text = text.replaceAll(term, '');
      }
      expect(latin.hasMatch(text), isFalse, reason: 'نص لاتيني ظاهر: $text');
    }
  });
}
