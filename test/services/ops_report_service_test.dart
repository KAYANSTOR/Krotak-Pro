import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/ops_report_service.dart';

import '../helpers/in_memory_repositories.dart';

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 17, 15, 0);
}

void main() {
  test('snapshot aggregates sales and message pipeline', () async {
    final messages = InMemoryMessageRepository();
    final sales = InMemorySaleRepository();
    final tx = InMemoryTransactionRepository();
    final cards = InMemoryCardRepository();
    final now = DateTime.utc(2026, 9, 17, 12);

    await messages.save(
      IncomingMessage(
        id: 'r1',
        sender: 'JAIB',
        body: 'x',
        receivedAt: now,
        status: MessageProcessingStatus.rejected,
      ),
    );
    await messages.save(
      IncomingMessage(
        id: 's1',
        sender: 'JAIB',
        body: 'y',
        receivedAt: now,
        status: MessageProcessingStatus.sending,
      ),
    );
    await cards.save(
      const Card(
        id: 'c1',
        categoryId: 'cat',
        serialNumber: 'SN1',
        secretCode: 'SC1',
        status: CardStatus.available,
      ),
    );
    await sales.save(
      Sale(
        id: 'sale1',
        customerId: 'cust',
        cardId: 'c1',
        amount: const Money(minorUnits: 50000, currencyCode: 'YER'),
        status: TransactionStatus.completed,
        createdAt: now,
      ),
    );

    final svc = OpsReportService(
      messages: messages,
      sales: sales,
      transactions: tx,
      cards: cards,
      clock: _Clock(),
    );
    final result = await svc.snapshot();
    expect(result, isA<Success<OpsSnapshot>>());
    final s = (result as Success<OpsSnapshot>).value;
    expect(s.rejectedCount, 1);
    expect(s.sendingCount, 1);
    expect(s.availableCards, 1);
    expect(s.dailySalesCount, 1);
    expect(s.dailySalesMinor, 50000);
  });
}
