import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, AppSetting, Transaction;
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/services/receipt_image_service.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/net/net_transaction_detail_sheet.dart';
import 'package:net_app/ui/widgets/net/transaction_receipt_card.dart';

/// WP-8 (D5) — صورة إشعار العملية: تُرسم بطاقة عربية RTL إلى PNG حقيقي،
/// «حفظ» يكتب صورة في الصور عبر قناة التخزين، و«مشاركة» تشارك صورة لا نصًا.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel('com.kayan.net/storage');
  late List<MethodCall> storageCalls;

  final receipt = Transaction(
    id: 'tx-1',
    type: TransactionType.deposit,
    status: TransactionStatus.completed,
    amount: const Money(minorUnits: 25000, currencyCode: 'YER'),
    reference: 'REF-1',
    createdAt: DateTime.utc(2026, 10, 10, 12),
  );

  setUp(() {
    storageCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
      storageCalls.add(call);
      return <String, Object?>{
        'path': 'content://images/krotak/إشعار.png',
        'uri': 'content://images/krotak/إشعار.png',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  test('اسم ملف الصورة عربي ومفهوم', () {
    expect(ReceiptImageService.fileNameFor('REF-1'), 'إشعار-REF-1.png');
    expect(ReceiptImageService.fileNameFor('a/b c'), 'إشعار-a-b-c.png');
    expect(ReceiptImageService.fileNameFor('   '), 'إشعار-عملية.png');
  });

  test('يكشف ترويسة PNG', () {
    expect(
      ReceiptImageService.isPng(Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0])),
      isTrue,
    );
    expect(ReceiptImageService.isPng(Uint8List.fromList(<int>[1, 2, 3, 4])), isFalse);
  });

  testWidgets('ترسم البطاقة إلى PNG حقيقي غير فارغ', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKayanLightTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: const SizedBox(
              width: 380,
              child: TransactionReceiptCard(
                amountText: '250.00',
                currencyLabel: 'ر.ي',
                reference: 'REF-1',
                typeLabel: 'إيداع',
                statusLabel: 'مكتملة',
                dateLabel: '10/10/2026 (12:00 م)',
                beneficiaryLabel: 'عميل تجريبي',
                isInflow: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Uint8List? bytes;
    await tester.runAsync(() async {
      bytes = await const ReceiptImageService().capture(boundaryKey);
    });

    expect(bytes, isNotNull, reason: 'فشل رسم بطاقة الإشعار');
    expect(ReceiptImageService.isPng(bytes!), isTrue, reason: 'الناتج ليس PNG');
    expect(bytes!.length, greaterThan(1000), reason: 'صورة فارغة أو تالفة');
  });

  testWidgets('زر الحفظ يكتب صورة عبر قناة التخزين لا ملف TXT', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups'),
    );
    addTearDown(() async {
      await container.dispose();
      await database.close();
    });

    // ورقة التفاصيل أطول من الشاشة الافتراضية للاختبار: نوسّع السطح حتى
    // تكون أزرار الحفظ/المشاركة قابلة للنقر فعلاً.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        container: container,
        child: MaterialApp(
          theme: buildKayanLightTheme(),
          home: Scaffold(
            body: NetTransactionDetailSheet(transaction: receipt),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TransactionReceiptCard), findsOneWidget);
    expect(find.text('حفظ'), findsOneWidget);
    expect(find.text('مشاركة'), findsOneWidget);
    expect(find.textContaining('نصية'), findsNothing);

    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(storageCalls, isNotEmpty, reason: 'لم تُستدعَ قناة التخزين لحفظ الصورة');
    final call = storageCalls.first;
    expect(call.method, 'saveImageToPictures');
    final args = call.arguments as Map;
    final name = args['fileName'] as String;
    expect(name.startsWith('إشعار-'), isTrue);
    expect(name.endsWith('.png'), isTrue);
  });
}
