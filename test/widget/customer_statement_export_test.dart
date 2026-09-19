import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/ui/widgets/customer_statement_export.dart';

void main() {
  test('buildCustomerStatementText includes name, phone, balance and txs', () {
    const customer = Customer(
      id: 'c1',
      displayName: 'علي',
      status: CustomerStatus.active,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    const ids = [
      CustomerIdentifier(
        id: 'i1',
        customerId: 'c1',
        type: CustomerIdentifierType.phoneNumber,
        value: '770000000',
        isPrimary: true,
      ),
    ];
    const balance = Money(minorUnits: 150000, currencyCode: 'YER');
    final txs = [
      Transaction(
        id: 't1',
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 50000, currencyCode: 'YER'),
        createdAt: DateTime.utc(2026, 9, 19, 10),
        customerId: 'c1',
        reference: 'sale-1',
      ),
    ];
    final text = buildCustomerStatementText(
      customer: customer,
      identifiers: ids,
      balance: balance,
      recent: txs,
      formatMoney: (m) => m == null ? '—' : '${m.minorUnits}',
      formatTime: (t) => '${t.day}/${t.month}',
    );
    expect(text, contains('علي'));
    expect(text, contains('770000000'));
    expect(text, contains('150000'));
    expect(text, contains('sale-1'));
    expect(text, contains('-50000'));
  });
}
