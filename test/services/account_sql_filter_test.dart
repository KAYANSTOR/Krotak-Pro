import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/account_sql_filter.dart';
import 'package:net_app/domain/entities/account_sql_sort.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalTransactionRepository transactions;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    transactions = LocalTransactionRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCustomer(String id, String name, {CustomerStatus status = CustomerStatus.active, String? phone}) async {
    final now = DateTime.utc(2026, 10, 1);
    await customers.save(Customer(
      id: id,
      displayName: name,
      status: status,
      createdAt: now,
      updatedAt: now,
    ));
    if (phone != null) {
      await customers.saveIdentifier(CustomerIdentifier(
        id: 'id-$id',
        customerId: id,
        type: CustomerIdentifierType.phoneNumber,
        value: phone,
        isPrimary: true,
      ));
    }
  }

  Future<void> ledger(String id, String customerId, TransactionType type, int minor, {TransactionStatus status = TransactionStatus.completed}) async {
    await transactions.append(Transaction(
      id: id,
      type: type,
      status: status,
      amount: Money(minorUnits: minor, currencyCode: 'YER'),
      createdAt: DateTime.utc(2026, 10, 1),
      customerId: customerId,
    ));
  }

  test('debtor filter uses completed signed ledger and skips merged', () async {
    await seedCustomer('debt', 'مدين', phone: '777000001');
    await seedCustomer('credit', 'دائن', phone: '777000002');
    await seedCustomer('zero', 'صفر', phone: '777000003');
    await seedCustomer('merged', 'مدمج', status: CustomerStatus.merged, phone: '777000004');
    await seedCustomer('pending-only', 'معلّق', phone: '777000005');
    await ledger('t1', 'debt', TransactionType.sale, 1500);
    await ledger('t2', 'credit', TransactionType.deposit, 800);
    await ledger('t3', 'merged', TransactionType.sale, 900);
    await ledger('t4', 'pending-only', TransactionType.sale, 400, status: TransactionStatus.pending);

    final debtors = await customers.searchFilteredPage('', filter: AccountSqlFilter.debtor);
    expect((debtors as Success<List<Customer>>).value.map((c) => c.id), ['debt']);

    final creditors = await customers.searchFilteredPage('', filter: AccountSqlFilter.creditor);
    expect((creditors as Success<List<Customer>>).value.map((c) => c.id), ['credit']);

    final zeros = await customers.searchFilteredPage('', filter: AccountSqlFilter.zero);
    final zeroIds = (zeros as Success<List<Customer>>).value.map((c) => c.id).toList();
    expect(zeroIds, containsAll(['zero', 'pending-only']));
    expect(zeroIds, isNot(contains('merged')));
    expect(zeroIds, isNot(contains('debt')));
  });

  test('unlinked filter ignores customers with a phone identifier', () async {
    await seedCustomer('linked', 'برقم', phone: '777111222');
    await seedCustomer('plain', 'بلا');
    final page = await customers.searchFilteredPage('', filter: AccountSqlFilter.unlinked);
    expect((page as Success<List<Customer>>).value.map((c) => c.id), ['plain']);
  });

  test('balance sort is applied in SQL before limit and offset', () async {
    await seedCustomer('low', 'منخفض', phone: '777200001');
    await seedCustomer('mid', 'متوسط', phone: '777200002');
    await seedCustomer('high', 'مرتفع', phone: '777200003');
    await ledger('s1', 'low', TransactionType.sale, 900);
    await ledger('s2', 'mid', TransactionType.deposit, 100);
    await ledger('s3', 'high', TransactionType.deposit, 2500);

    final desc = await customers.searchFilteredPage(
      '',
      filter: AccountSqlFilter.all,
      sort: AccountSqlSort.balanceDesc,
    );
    expect((desc as Success<List<Customer>>).value.map((c) => c.id), ['high', 'mid', 'low']);

    final ascPage = await customers.searchFilteredPage(
      '',
      filter: AccountSqlFilter.all,
      sort: AccountSqlSort.balanceAsc,
      limit: 1,
      offset: 1,
    );
    expect((ascPage as Success<List<Customer>>).value.map((c) => c.id), ['mid']);
  });
}
