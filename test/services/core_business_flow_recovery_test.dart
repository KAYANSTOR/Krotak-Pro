import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction, IncomingMessage, CustomerIdentifier, AuditLog;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalCardRepository cards;
  late LocalMessageRepository messages;
  late LocalTransactionRepository transactions;
  late LocalSaleRepository sales;
  late LocalAuditLogRepository audits;
  late LocalCardCategoryRepository categories;
  late DriftUnitOfWork uow;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalCustomerBalanceService balanceService;
  late LocalCardCatalogService catalogService;
  late LocalCardInventoryService inventoryService;
  late LocalSaleService saleService;
  late _FakeSender sender;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    cards = LocalCardRepository(database);
    messages = LocalMessageRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    audits = LocalAuditLogRepository(database);
    categories = LocalCardCategoryRepository(database);
    uow = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 12, 1));
    ids = SequentialIdGenerator();
    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    balanceService = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    catalogService = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    inventoryService = LocalCardInventoryService(
      categories: categories,
      cards: cards,
      unitOfWork: uow,
    );
    saleService = LocalSaleService(
      customers: customers,
      categories: categories,
      cards: cards,
      sales: sales,
      transactions: transactions,
      balances: balanceService,
      inventory: inventoryService,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    sender = _FakeSender();
  });

  tearDown(() => database.close());

  test('recovers after SMS success recorded before financial commit without sending again', () async {
    final customer = (await customerService.create(
      displayName: 'Ali',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733000000',
    ) as Success<Customer>).value;

    await catalogService.saveCategory(
      const CardCategory(
        id: 'cat-200',
        name: 'Value 200',
        faceValue: Money(minorUnits: 200, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    await catalogService.importCards(
      categoryId: 'cat-200',
      drafts: const [
        CardImportDraft(serialNumber: 'SN-RECOVERY', secretCode: 'SECRET-RECOVERY'),
      ],
    );
    await messages.save(
      IncomingMessage(
        id: 'm-recovery',
        sender: 'bank',
        body: 'transfer',
        receivedAt: clock.now(),
        status: MessageProcessingStatus.failed,
        externalReference: 'bank:RECOVERY-1',
        customerIdentifier: '733000000',
      ),
    );

    const reserved = await inventoryService.reserveAvailableCard(
      categoryId: 'cat-200',
      reservationId: 'transfer-reservation:RECOVERY-1',
      now: clock.now(),
      expiresAt: clock.now().add(const Duration(minutes: 5)),
    );
    final card = (reserved as Success<Card>).value;
    await balanceService.credit(
      customerId: customer.id,
      amount: const Money(minorUnits: 200, currencyCode: 'YER'),
      reference: 'RECOVERY-1',
    );
    await audits.append(
      AuditLog(
        id: 'audit-delivery',
        entityType: 'message',
        entityId: 'm-recovery',
        action: 'sms_delivery_succeeded',
        occurredAt: clock.now(),
        payloadJson:
            '{"operationId":"RECOVERY-1","cardId":"${card.id}","categoryId":"cat-200","reservationId":"transfer-reservation:RECOVERY-1","destination":"733000000"}',
      ),
    );

    final processor = LocalTransferProcessor(
      messages: messages,
      customers: customers,
      balances: balanceService,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
      categories: categories,
      cards: cards,
      inventory: inventoryService,
      transactions: transactions,
      reservedSales: saleService,
      messageSender: sender,
    );

    final result = await processor.process(
      const ParsedTransfer(
        messageId: 'm-recovery',
        amount: Money(minorUnits: 200, currencyCode: 'YER'),
        customerIdentifier: '733000000',
        identifierType: TransferIdentifierType.phone,
        reference: 'RECOVERY-1',
      ),
    );

    final soldCard = await cards.findById(card.id);
    final sale = await sales.findById('RECOVERY-1');
    final ledger = await transactions.findByReference('sale-op:RECOVERY-1');

    expect(result, isA<Success<Transaction>>());
    expect(sender.calls, 0);
    expect((soldCard as Success<Card?>).value?.status, CardStatus.sold);
    expect((sale as Success<Sale?>).value?.id, 'RECOVERY-1');
    expect((ledger as Success<Transaction?>).value?.reference, 'sale-op:RECOVERY-1');
  });
}

final class _FakeSender implements MessageSender {
  int calls = 0;

  @override
  Future<Result<void>> send({required String destination, required String body}) async {
    calls++;
    return const Success<void>(null);
  }
}
