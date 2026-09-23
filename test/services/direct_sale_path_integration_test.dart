import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction;
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/ui/app_scope.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/dashboard/direct_sale_sheet.dart';

/// تكامل مسار البيع المباشر: مجال (sellManual) + واجهة (DirectSaleSheet).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AppContainer container;

  /// 200 ر.ي → 20000 وحدة صغرى (نفس منطق الحقل: major * 100).
  const face = Money(minorUnits: 20000, currencyCode: 'YER');

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-backups-direct-sale'),
      templates: const [
        TransferTemplate(
          id: 'tpl-ds',
          name: 'تحويل',
          pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
          isActive: true,
        ),
      ],
    );
    AppScope.register(container);
  });

  tearDown(() async {
    AppScope.unregister(container);
    await container.dispose();
    await database.close();
  });

  Future<void> seedStock({int cards = 3}) async {
    final cat = await container.catalogService.saveCategory(
      const CardCategory(
        id: 'cat-ds-200',
        name: 'فئة بيع مباشر 200',
        faceValue: face,
        isActive: true,
      ),
    );
    expect(cat, isA<Success<CardCategory>>());

    final drafts = List.generate(
      cards,
      (i) => CardImportDraft(
        serialNumber: 'SN-DS-$i',
        secretCode: 'PIN-DS-$i',
      ),
    );
    final imported = await container.catalogService.importCards(
      categoryId: 'cat-ds-200',
      drafts: drafts,
    );
    expect(imported, isA<Success<int>>());
    expect((imported as Success<int>).value, cards);
  }

  group('domain sellManual', () {
    test('cash sale: creates customer, deposits, sells one card, idempotent op id',
        () async {
      await seedStock();

      final first = await container.saleService.sellManual(
        phone: '777123456',
        displayName: 'مشتري نقدي',
        amount: face,
        method: ManualSaleMethod.cash,
        operationId: 'op-cash-1',
      );
      expect(first, isA<Success<Sale>>());
      final sale = (first as Success<Sale>).value;
      expect(sale.id, 'op-cash-1');
      expect(sale.amount.minorUnits, face.minorUnits);
      expect(sale.status, TransactionStatus.completed);

      final customer = await container.customers.findByIdentifier('777123456');
      expect(customer, isA<Success<Customer?>>());
      expect((customer as Success<Customer?>).value?.displayName, 'مشتري نقدي');

      final stock = await container.cards.findByCategory('cat-ds-200');
      final cards = (stock as Success<List<Card>>).value;
      expect(cards.where((c) => c.status == CardStatus.sold), hasLength(1));
      expect(cards.where((c) => c.status == CardStatus.available), hasLength(2));

      final second = await container.saleService.sellManual(
        phone: '777123456',
        displayName: 'مشتري نقدي',
        amount: face,
        method: ManualSaleMethod.cash,
        operationId: 'op-cash-1',
      );
      expect(second, isA<Success<Sale>>());
      expect((second as Success<Sale>).value.id, 'op-cash-1');
      final stock2 = await container.cards.findByCategory('cat-ds-200');
      expect(
        (stock2 as Success<List<Card>>)
            .value
            .where((c) => c.status == CardStatus.sold),
        hasLength(1),
      );
    });

    test('credit sale records debt without cash deposit reference', () async {
      await seedStock(cards: 1);

      final r = await container.saleService.sellManual(
        phone: '777999888',
        displayName: 'مشتري آجل',
        amount: face,
        method: ManualSaleMethod.credit,
        operationId: 'op-credit-1',
      );
      expect(r, isA<Success<Sale>>());

      final txns = await container.transactions.findByCustomer(
        (r as Success<Sale>).value.customerId,
      );
      expect(txns, isA<Success<List<Transaction>>>());
      final list = (txns as Success<List<Transaction>>).value;
      expect(list.any((t) => t.type == TransactionType.sale), isTrue);
      expect(
        list.any((t) => t.reference?.startsWith('manual-cash:') == true),
        isFalse,
      );
    });

    test('unknown amount fails without consuming stock', () async {
      await seedStock(cards: 1);

      final r = await container.saleService.sellManual(
        phone: '777111000',
        displayName: 'مبلغ خاطئ',
        amount: const Money(minorUnits: 99999, currencyCode: 'YER'),
        method: ManualSaleMethod.cash,
        operationId: 'op-bad-amount',
      );
      expect(r, isA<Failure<Sale>>());
      expect((r as Failure<Sale>).error.code, 'category_not_found_for_amount');

      final stock = await container.cards.findByCategory('cat-ds-200');
      expect(
        (stock as Success<List<Card>>)
            .value
            .every((c) => c.status == CardStatus.available),
        isTrue,
      );
    });

    test('phone prefix suggestions return seeded customer', () async {
      final created = await container.customerService.create(
        displayName: 'عميل مقترح',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733445566',
      );
      expect(created, isA<Success<Customer>>());

      final suggestions =
          await container.customers.suggestPhonesByPrefix('733', limit: 8);
      expect(suggestions, isA<Success<List<CustomerPhoneSuggestion>>>());
      final list =
          (suggestions as Success<List<CustomerPhoneSuggestion>>).value;
      expect(list.any((s) => s.phone.contains('733445566')), isTrue);
    });
  });

  group('UI DirectSaleSheet', () {
    Future<void> pumpSheetHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildKayanLightTheme(),
          home: AppScope(
            container: container,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    return Center(
                      child: FilledButton(
                        onPressed: () => DirectSaleSheet.show(context),
                        child: const Text('فتح البيع'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('validation: invalid phone shows error, no sale', (tester) async {
      await seedStock(cards: 1);
      await pumpSheetHost(tester);

      await tester.tap(find.text('فتح البيع'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('بيع مباشر - يدوي'), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsWidgets);
      await tester.enterText(fields.at(0), '12345');
      await tester.enterText(fields.at(1), '200');
      await tester.tap(find.text('تأكيد البيع المباشر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('9 أرقام'), findsOneWidget);

      final stock = await container.cards.findByCategory('cat-ds-200');
      expect(
        (stock as Success<List<Card>>)
            .value
            .every((c) => c.status == CardStatus.available),
        isTrue,
      );
    });

    testWidgets('cash path: fill form → confirm → sheet closes and card sold',
        (tester) async {
      await seedStock(cards: 2);
      await pumpSheetHost(tester);

      await tester.tap(find.text('فتح البيع'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('بيع مباشر - يدوي'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '777654321');
      await tester.enterText(fields.at(1), '200');
      await tester.enterText(fields.at(2), 'عميل الواجهة');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('تأكيد البيع المباشر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('بيع مباشر - يدوي'), findsNothing);

      final stock = await container.cards.findByCategory('cat-ds-200');
      final sold =
          (stock as Success<List<Card>>).value.where((c) => c.status == CardStatus.sold);
      expect(sold, hasLength(1));

      final customer =
          await container.customers.findByIdentifier('777654321');
      expect((customer as Success<Customer?>).value?.displayName, 'عميل الواجهة');
    });

    testWidgets('phone suggestions appear while typing known prefix',
        (tester) async {
      await container.customerService.create(
        displayName: 'مقترح واجهة',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: '733998877',
      );
      await seedStock(cards: 1);
      await pumpSheetHost(tester);

      await tester.tap(find.text('فتح البيع'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField).first, '733');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('733998877'), findsWidgets);
      expect(find.textContaining('مقترح واجهة'), findsWidgets);
    });
  });
}
