import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/pos_statement_pdf_rows.dart';

void main() {
  test('POS statement PDF rows keep balance, limit, and movements', () {
    final rows = buildPosStatementPdfRows(
      balanceMinor: -150000,
      creditLimitMinor: 500000,
      phone: '777000111',
      lines: [
        PosStatementPdfLine(
          occurredAt: DateTime.utc(2026, 10, 1, 9, 30),
          kind: 'تسوية',
          description: 'حوالة',
          amountMinor: 50000,
          status: 'مكتملة',
        ),
      ],
    );

    expect(rows, hasLength(4));
    expect(rows[0].cells[2], '777000111');
    expect(rows[1].cells[1], 'مديونية');
    expect(rows[1].cells[3], '1500.00');
    expect(rows[2].cells[3], '5000.00');
    expect(rows[3].cells[1], 'تسوية');
    expect(rows[3].cells[2], 'حوالة');
    expect(rows[3].cells[3], '500.00');
  });

  test('missing credit limit stays unmarked instead of zero', () {
    final rows = buildPosStatementPdfRows(
      balanceMinor: 0,
      creditLimitMinor: null,
      phone: ' ',
      lines: const [],
    );

    expect(rows[0].cells[2], '—');
    expect(rows[1].cells[1], 'رصيد دائن');
    expect(rows[2].cells[2], 'غير محدد');
    expect(rows[2].cells[4], 'غير مفعّل');
  });

  test('ledger export includes every movement, oldest first', () {
    final lines = posStatementLinesFromLedger([
      Transaction(
        id: 'sale-1',
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 20000, currencyCode: 'YER'),
        createdAt: DateTime.utc(2026, 10, 2, 8),
        reference: 'كرت 200',
      ),
      Transaction(
        id: 'set-1',
        type: TransactionType.settlement,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 5000, currencyCode: 'YER'),
        createdAt: DateTime.utc(2026, 9, 1, 12),
      ),
      Transaction(
        id: 'adv-1',
        type: TransactionType.advance,
        status: TransactionStatus.rejected,
        amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
        createdAt: DateTime.utc(2026, 9, 15),
        reference: '   ',
      ),
    ]);

    expect(lines.map((line) => line.kind).toList(), ['تسوية', 'سلفة', 'بيع']);
    expect(lines[0].description, 'تسوية');
    expect(lines[1].status, 'مرفوضة');
    expect(lines[1].description, 'سلفة');
    expect(lines[2].description, 'كرت 200');
    expect(lines[2].status, 'مكتملة');
  });

  test('prior customer movements stay out of the POS statement', () {
    final linkedAt = DateTime.utc(2026, 10, 1, 0);
    final slice = slicePosStatementLedger(
      [
        Transaction(
          id: 'old-sale',
          type: TransactionType.sale,
          status: TransactionStatus.completed,
          amount: const Money(minorUnits: 30000, currencyCode: 'YER'),
          createdAt: DateTime.utc(2026, 9, 20),
          reference: 'بيع قبل الربط',
        ),
        Transaction(
          id: 'old-deposit',
          type: TransactionType.deposit,
          status: TransactionStatus.completed,
          amount: const Money(minorUnits: 10000, currencyCode: 'YER'),
          createdAt: DateTime.utc(2026, 9, 21),
        ),
        Transaction(
          id: 'at-link',
          type: TransactionType.sale,
          status: TransactionStatus.completed,
          amount: const Money(minorUnits: 4000, currencyCode: 'YER'),
          createdAt: linkedAt,
          reference: 'أول بيع للنقطة',
        ),
      ],
      linkedAt: linkedAt,
    );

    expect(slice.excludedCount, 2);
    expect(slice.openingBalanceMinor, -20000);
    expect(slice.lines, hasLength(1));
    expect(slice.lines.single.description, 'أول بيع للنقطة');

    final rows = buildPosStatementPdfRows(
      balanceMinor: -24000,
      creditLimitMinor: 100000,
      phone: '777',
      lines: slice.lines,
      openingBalanceMinor: slice.openingBalanceMinor,
      excludedCount: slice.excludedCount,
    );
    expect(rows[3].cells[1], 'رصيد مرحّل');
    expect(rows[3].cells[3], '200.00');
    expect(rows[3].cells[4], 'مديونية قبل الربط');
    expect(rows[4].cells[2], 'أول بيع للنقطة');
  });
}
