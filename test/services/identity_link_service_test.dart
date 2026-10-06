import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction, IncomingMessage;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/local_account_merge_service.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_identity_link_service.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalTransactionRepository transactions;
  late LocalIdentityLinkService link;
  late LocalCustomerBalanceService balanceService;
  late LocalCustomerService customerService;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    transactions = LocalTransactionRepository(database);
    final sales = LocalSaleRepository(database);
    final auditLogs = LocalAuditLogRepository(database);
    final uow = DriftUnitOfWork(database);
    final clock = FixedClock(DateTime(2026, 1, 1, 12));
    final ids = SequentialIdGenerator();
    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    balanceService = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    link = LocalIdentityLinkService(
      customers: customers,
      customerService: customerService,
      mergeService: LocalAccountMergeService(
        customers: customers,
        transactions: transactions,
        auditLogs: auditLogs,
        unitOfWork: uow,
        clock: clock,
        ids: ids,
        historyMovers: [transactions, sales],
      ),
    );
  });

  tearDown(() async => database.close());

  Future<Customer> createAlt(String ref) async {
    final r = await customerService.create(
      displayName: 'مودع مخفي',
      identifierType: CustomerIdentifierType.externalReference,
      identifierValue: ref,
      status: CustomerStatus.provisional,
    );
    return (r as Success<Customer>).value;
  }

  Future<Customer> createReal(String name, String phone) async {
    final r = await customerService.create(
      displayName: name,
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
    );
    return (r as Success<Customer>).value;
  }

  Future<void> deposit(String id, String customerId, int minor) async {
    await transactions.append(
      Transaction(
        id: id,
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: Money(minorUnits: minor, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 1),
        customerId: customerId,
        reference: id,
      ),
    );
  }

  test('a free phone number is bound to the same account', () async {
    final alt = await createAlt('ALT-1');
    final r = await link.link(altCustomerId: alt.id, phone: '770123456');
    expect(r, isA<Success<Customer>>());
    expect((r as Success<Customer>).value.id, alt.id);
    final owner = await customers.findByIdentifier('770123456');
    expect((owner as Success<Customer?>).value?.id, alt.id);
  });

  test('a phone owned by another account merges the alt account into it with its history', () async {
    final alt = await createAlt('ALT-2');
    final real = await createReal('أحمد', '771000000');
    await deposit('t-alt', alt.id, 5000);
    await deposit('t-real', real.id, 1000);

    final preview = await link.preview(altCustomerId: alt.id, phone: '771000000');
    expect((preview as Success<IdentityLinkPreview>).value.willMerge, isTrue);

    final r = await link.link(altCustomerId: alt.id, phone: '771000000');
    expect((r as Success<Customer>).value.id, real.id);

    final source = await customers.findById(alt.id);
    expect((source as Success<Customer?>).value?.status, CustomerStatus.merged);

    final balance = await balanceService.getBalance(customerId: real.id, currencyCode: 'YER');
    expect((balance as Success<Money>).value.minorUnits, 6000);
  });

  test('an account that already has a phone cannot be linked again', () async {
    final real = await createReal('سالم', '772000000');
    final r = await link.link(altCustomerId: real.id, phone: '773000000');
    expect(r, isA<Failure<Customer>>());
  });

  test('an invalid phone is rejected', () async {
    final alt = await createAlt('ALT-3');
    final r = await link.link(altCustomerId: alt.id, phone: 'abc');
    expect(r, isA<Failure<Customer>>());
  });
}
