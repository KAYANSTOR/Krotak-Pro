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

  Future<void> ledger(String id, String customerId, TransactionType type, int minor, {TransactionStatus status = TransactionStatus.completed, String currencyCode = 'YER'}) async {
    await transactions.append(Transaction(
      id: id,
      type: type,
      status: status,
      amount: Money(minorUnits: minor, currencyCode: currencyCode),
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

  test('all filter pages after SQL balance order', () async {
    await seedCustomer('low', 'منخفض', phone: '777300001');
    await seedCustomer('mid', 'متوسط', phone: '777300002');
    await seedCustomer('high', 'مرتفع', phone: '777300003');
    await ledger('p1', 'low', TransactionType.sale, 900);
    await ledger('p2', 'mid', TransactionType.deposit, 100);
    await ledger('p3', 'high', TransactionType.deposit, 2500);

    final first = await customers.searchFilteredPage(
      '',
      filter: AccountSqlFilter.all,
      sort: AccountSqlSort.balanceDesc,
      limit: 2,
      offset: 0,
    );
    expect((first as Success<List<Customer>>).value.map((c) => c.id), ['high', 'mid']);

    final second = await customers.searchFilteredPage(
      '',
      filter: AccountSqlFilter.all,
      sort: AccountSqlSort.balanceDesc,
      limit: 2,
      offset: 2,
    );
    expect((second as Success<List<Customer>>).value.map((c) => c.id), ['low']);
  });

  test('countFiltered ignores page size and skips merged', () async {
    await seedCustomer('debt', 'مدين', phone: '777400001');
    await seedCustomer('credit', 'دائن', phone: '777400002');
    await seedCustomer('merged', 'مدمج', status: CustomerStatus.merged, phone: '777400003');
    await ledger('c1', 'debt', TransactionType.sale, 500);
    await ledger('c2', 'credit', TransactionType.deposit, 700);

    final all = await customers.countFiltered('', filter: AccountSqlFilter.all);
    expect((all as Success<int>).value, 2);

    final page = await customers.searchFilteredPage(
      '',
      filter: AccountSqlFilter.all,
      limit: 1,
      offset: 0,
    );
    expect((page as Success<List<Customer>>).value, hasLength(1));

    final debtors = await customers.countFiltered('', filter: AccountSqlFilter.debtor);
    expect((debtors as Success<int>).value, 1);

    final named = await customers.countFiltered('دائن', filter: AccountSqlFilter.all);
    expect((named as Success<int>).value, 1);
  });

  test('countFilterBuckets returns every chip from one query', () async {
    await seedCustomer('debt', 'مدين', phone: '777500001');
    await seedCustomer('credit', 'دائن', phone: '777500002');
    await seedCustomer('zero', 'صفر', phone: '777500003');
    await seedCustomer('temp', 'مؤقت', status: CustomerStatus.provisional);
    await seedCustomer('merged', 'مدمج', status: CustomerStatus.merged, phone: '777500004');
    await ledger('b1', 'debt', TransactionType.sale, 500);
    await ledger('b2', 'credit', TransactionType.deposit, 700);

    final buckets = await customers.countFilterBuckets('');
    final counts = (buckets as Success<AccountFilterCounts>).value;
    expect(counts.all, 4);
    expect(counts.debtor, 1);
    expect(counts.creditor, 1);
    expect(counts.zero, 2);
    expect(counts.provisional, 1);
    expect(counts.unlinked, 1);
    expect(counts[AccountSqlFilter.all], counts.all);
  });

  test('sumLedgerSides totals debtor and creditor without page limit', () async {
    await seedCustomer('debt', 'مدين', phone: '777600001');
    await seedCustomer('debt2', 'مدين ثان', phone: '777600002');
    await seedCustomer('credit', 'دائن', phone: '777600003');
    await seedCustomer('merged', 'مدمج', status: CustomerStatus.merged, phone: '777600004');
    await ledger('t1', 'debt', TransactionType.sale, 500);
    await ledger('t2', 'debt2', TransactionType.sale, 300);
    await ledger('t3', 'credit', TransactionType.deposit, 700);
    await ledger('t4', 'merged', TransactionType.sale, 9000);

    final totals = await customers.sumLedgerSides('');
    final value = (totals as Success<AccountLedgerTotals>).value;
    expect(value.debtorMinorUnits, 800);
    expect(value.creditorMinorUnits, 700);

    final named = await customers.sumLedgerSides('دائن');
    final namedValue = (named as Success<AccountLedgerTotals>).value;
    expect(namedValue.debtorMinorUnits, 0);
    expect(namedValue.creditorMinorUnits, 700);
  });

  test('sumLedgerSides respects the active filter chip', () async {
    await seedCustomer('debt', 'مدين', phone: '777700001');
    await seedCustomer('credit', 'دائن', phone: '777700002');
    await seedCustomer('temp', 'مؤقت مدين', status: CustomerStatus.provisional);
    await seedCustomer('plain', 'بلا رقم');
    await ledger('f1', 'debt', TransactionType.sale, 500);
    await ledger('f2', 'credit', TransactionType.deposit, 700);
    await ledger('f3', 'temp', TransactionType.sale, 200);
    await ledger('f4', 'plain', TransactionType.deposit, 50);

    final debtors = await customers.sumLedgerSides(
      '',
      filter: AccountSqlFilter.debtor,
    );
    final debtorTotals = (debtors as Success<AccountLedgerTotals>).value;
    expect(debtorTotals.debtorMinorUnits, 700);
    expect(debtorTotals.creditorMinorUnits, 0);

    final provisional = await customers.sumLedgerSides(
      '',
      filter: AccountSqlFilter.provisional,
    );
    final provisionalTotals = (provisional as Success<AccountLedgerTotals>).value;
    expect(provisionalTotals.debtorMinorUnits, 200);
    expect(provisionalTotals.creditorMinorUnits, 0);

    final unlinked = await customers.sumLedgerSides(
      '',
      filter: AccountSqlFilter.unlinked,
    );
    final unlinkedTotals = (unlinked as Success<AccountLedgerTotals>).value;
    expect(unlinkedTotals.debtorMinorUnits, 200);
    expect(unlinkedTotals.creditorMinorUnits, 50);
  });
}


  test('sumLedgerSidesByCurrency keeps YER chip membership and sums other currencies', () async {
    await seedCustomer('debt', 'مدين', phone: '777800001');
    await seedCustomer('credit', 'دائن', phone: '777800002');
    await seedCustomer('merged', 'مدمج', status: CustomerStatus.merged, phone: '777800003');
    await ledger('y1', 'debt', TransactionType.sale, 500);
    await ledger('u1', 'debt', TransactionType.deposit, 250, currencyCode: 'USD');
    await ledger('y2', 'credit', TransactionType.deposit, 700);
    await ledger('u2', 'credit', TransactionType.sale, 100, currencyCode: 'USD');
    await ledger('ym', 'merged', TransactionType.sale, 9000, currencyCode: 'USD');

    final all = await customers.sumLedgerSidesByCurrency('');
    final rows = (all as Success<List<AccountCurrencyLedgerTotals>>).value;
    expect(rows.map((row) => row.currencyCode), ['YER', 'USD']);
    expect(rows.first.debtorMinorUnits, 500);
    expect(rows.first.creditorMinorUnits, 700);
    expect(rows.last.debtorMinorUnits, 100);
    expect(rows.last.creditorMinorUnits, 250);
    expect(otherCurrencyTotalsLabel(rows), 'USD: مدين 1.00 / دائن 2.50');

    final debtors = await customers.sumLedgerSidesByCurrency(
      '',
      filter: AccountSqlFilter.debtor,
    );
    final debtorRows = (debtors as Success<List<AccountCurrencyLedgerTotals>>).value;
    final usd = debtorRows.singleWhere((row) => row.currencyCode == 'USD');
    expect(usd.creditorMinorUnits, 250);
    expect(usd.debtorMinorUnits, 0);
  });
