import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/services/local_message_retry_service.dart';
import 'package:net_app/domain/services/message_delivery_worker.dart';
import 'package:net_app/domain/services/message_retry_policy.dart';
import 'package:net_app/domain/services/services.dart';

import '../helpers/in_memory_repositories.dart';

final class _RecordingSender implements MessageSender {
  final List<({String destination, String body})> sent = [];
  AppFailure? failWith;

  @override
  Future<Result<void>> send({required String destination, required String body}) async {
    if (failWith != null) return Failure(failWith!);
    sent.add((destination: destination, body: body));
    return const Success(null);
  }
}

final class _SeqIds implements IdGenerator {
  var n = 0;
  @override
  String next(String prefix) => '$prefix-${++n}';
}

final class _FixedClock implements Clock {
  _FixedClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

void main() {
  late InMemoryMessageRepository messages;
  late InMemoryAuditLogRepository audits;
  late InMemoryCardRepository cards;
  late _RecordingSender sender;
  late LocalMessageRetryService retry;
  late _FixedClock clock;
  late MessageDeliveryWorker worker;

  setUp(() {
    messages = InMemoryMessageRepository();
    audits = InMemoryAuditLogRepository();
    cards = InMemoryCardRepository();
    sender = _RecordingSender();
    clock = _FixedClock(DateTime.utc(2026, 9, 17, 12, 0));
    retry = LocalMessageRetryService(
      auditLogs: audits,
      messages: messages,
      clock: clock,
      ids: _SeqIds(),
      policy: const MessageRetryPolicy(),
    );
    worker = MessageDeliveryWorker(
      messages: messages,
      auditLogs: audits,
      cards: cards,
      messageSender: sender,
      retryService: retry,
      clock: clock,
      ids: _SeqIds(),
    );
  });

  Future<void> seedCommittedFailedMessage() async {
    await messages.save(
      IncomingMessage(
        id: 'm1',
        sender: 'JAIB',
        body: 'transfer',
        receivedAt: clock.now().subtract(const Duration(minutes: 20)),
        status: MessageProcessingStatus.failed,
      ),
    );
    await cards.save(
      const Card(
        id: 'card-1',
        categoryId: 'cat-1',
        serialNumber: 'SN-9',
        secretCode: 'CODE-9',
        status: CardStatus.sold,
      ),
    );
    await audits.append(
      AuditLog(
        id: 'a1',
        entityType: 'message',
        entityId: 'm1',
        action: 'voucher_committed',
        occurredAt: clock.now().subtract(const Duration(minutes: 16)),
        payloadJson:
            '{"operationId":"op-1","cardId":"card-1","categoryId":"cat-1","reservationId":"res-1","destination":"733000000"}',
      ),
    );
  }

  test('resends same card after voucher_committed without second sale', () async {
    await seedCommittedFailedMessage();

    final report = await worker.tick();
    expect(report, isA<Success<DeliveryWorkerReport>>());
    final r = (report as Success<DeliveryWorkerReport>).value;
    expect(r.delivered, 1);
    expect(sender.sent, hasLength(1));
    expect(sender.sent.single.destination, '733000000');
    expect(sender.sent.single.body, contains('SN-9'));
    expect(sender.sent.single.body, contains('CODE-9'));

    final msg = await messages.findById('m1');
    expect((msg as Success<IncomingMessage?>).value!.status, MessageProcessingStatus.processed);
  });

  test('does not deliver before 15m when not otherwise due', () async {
    await messages.save(
      IncomingMessage(
        id: 'm2',
        sender: 'JAIB',
        body: 'transfer',
        receivedAt: clock.now(),
        status: MessageProcessingStatus.sending,
      ),
    );
    await cards.save(
      const Card(
        id: 'card-2',
        categoryId: 'cat-1',
        serialNumber: 'SN-2',
        secretCode: 'CODE-2',
        status: CardStatus.sold,
      ),
    );
    await audits.append(
      AuditLog(
        id: 'a2',
        entityType: 'message',
        entityId: 'm2',
        action: 'voucher_committed',
        occurredAt: clock.now().subtract(const Duration(minutes: 5)),
        payloadJson:
            '{"operationId":"op-2","cardId":"card-2","categoryId":"cat-1","reservationId":"res-2","destination":"733111111"}',
      ),
    );
    await audits.append(
      AuditLog(
        id: 'a2b',
        entityType: 'message',
        entityId: 'm2',
        action: 'message_retry_scheduled',
        occurredAt: clock.now(),
        payloadJson:
            '{"attempt":1,"nextRetryAt":"${clock.now().add(const Duration(minutes: 30)).toIso8601String()}","errorCode":"sms_delivery_failed"}',
      ),
    );

    final report = await worker.tick();
    final r = (report as Success<DeliveryWorkerReport>).value;
    expect(r.delivered, 0);
    expect(sender.sent, isEmpty);
  });

  test('records failure without releasing card identity', () async {
    await seedCommittedFailedMessage();
    sender.failWith = const AppFailure(code: 'sms_delivery_failed', message: 'modem down');

    final report = await worker.tick();
    final r = (report as Success<DeliveryWorkerReport>).value;
    expect(r.delivered, 0);
    expect(r.attempted, 1);

    final msg = await messages.findById('m1');
    expect((msg as Success<IncomingMessage?>).value!.status, MessageProcessingStatus.failed);
    final card = await cards.findById('card-1');
    expect((card as Success<Card?>).value!.status, CardStatus.sold);
  });
}
