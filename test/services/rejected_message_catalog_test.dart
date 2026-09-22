import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/rejected_message_catalog.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  group('RejectedMessageCatalog', () {
    test('maps out_of_stock audit to stock category', () async {
      final messages = _FakeMessages()
        ..store['m1'] = IncomingMessage(
          id: 'm1',
          sender: 'Jaib',
          body: 'تم تحويل 200 ريال الى 770123456 برقم العملية R1',
          receivedAt: DateTime.utc(2026, 9, 12),
          status: MessageProcessingStatus.rejected,
        );
      final audit = _FakeAudit()
        ..logs.add(
          AuditLog(
            id: 'a1',
            entityType: 'message',
            entityId: 'm1',
            action: 'transfer_out_of_stock',
            occurredAt: DateTime.utc(2026, 9, 12, 1),
          ),
        );
      final catalog = RejectedMessageCatalog(
        messages: messages,
        auditLogs: audit,
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'm1',
            amount: Money(minorUnits: 20000, currencyCode: 'YER'),
            customerIdentifier: '770123456',
            identifierType: TransferIdentifierType.phone,
            reference: 'R1',
          ),
        ),
      );

      final result = await catalog.listRejected();
      expect(result, isA<Success<List<RejectedMessageItem>>>());
      final item = (result as Success<List<RejectedMessageItem>>).value.single;
      expect(item.category, RejectionCategories.outOfStock);
      expect(item.phone, '770123456');
      expect(item.amount?.minorUnits, 20000);
    });

    test('pending_message_rejected maps to rejected-from-pending', () async {
      final messages = _FakeMessages()
        ..store['m2'] = IncomingMessage(
          id: 'm2',
          sender: 'BANK',
          body: 'x',
          receivedAt: DateTime.utc(2026, 9, 11),
          status: MessageProcessingStatus.rejected,
        );
      final audit = _FakeAudit()
        ..logs.add(
          AuditLog(
            id: 'a2',
            entityType: 'message',
            entityId: 'm2',
            action: 'pending_message_rejected',
            occurredAt: DateTime.utc(2026, 9, 11, 2),
            payloadJson: '{"reason":"رفض يدوي"}',
          ),
        );
      final catalog = RejectedMessageCatalog(
        messages: messages,
        auditLogs: audit,
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'm2',
            amount: Money(minorUnits: 1000, currencyCode: 'YER'),
            customerIdentifier: '770000000',
            identifierType: TransferIdentifierType.phone,
            reference: 'R2',
          ),
        ),
      );

      final result = await catalog.listRejected();
      final item = (result as Success<List<RejectedMessageItem>>).value.single;
      expect(item.category, RejectionCategories.rejectedFromPending);
      expect(item.reason, 'رفض يدوي');
    });

    test('isNew uses viewedAfter boundary', () async {
      final messages = _FakeMessages()
        ..store['old'] = IncomingMessage(
          id: 'old',
          sender: 'A',
          body: 'b',
          receivedAt: DateTime.utc(2026, 9, 1),
          status: MessageProcessingStatus.rejected,
        )
        ..store['new'] = IncomingMessage(
          id: 'new',
          sender: 'B',
          body: 'b',
          receivedAt: DateTime.utc(2026, 9, 12),
          status: MessageProcessingStatus.rejected,
        );
      final catalog = RejectedMessageCatalog(
        messages: messages,
        auditLogs: _FakeAudit(),
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'x',
            amount: Money(minorUnits: 100, currencyCode: 'YER'),
            customerIdentifier: '1',
            identifierType: TransferIdentifierType.phone,
            reference: 'r',
          ),
        ),
      );

      final result = await catalog.listRejected(
        viewedAfter: DateTime.utc(2026, 9, 10),
      );
      final items = (result as Success<List<RejectedMessageItem>>).value;
      expect(items.where((i) => i.isNew).map((i) => i.message.id), ['new']);
    });
  });
}

final class _FakeParser implements MessageParser {
  const _FakeParser(this.transfer);
  final ParsedTransfer transfer;
  @override
  Result<ParsedTransfer> parse(IncomingMessage message) => Success(
        ParsedTransfer(
          messageId: message.id,
          amount: transfer.amount,
          customerIdentifier: transfer.customerIdentifier,
          identifierType: transfer.identifierType,
          reference: transfer.reference,
        ),
      );
}

final class _FakeMessages implements MessageRepository {
  final store = <String, IncomingMessage>{};

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    store[message.id] = message;
    return const Success(null);
  }

  @override
  Future<Result<IncomingMessage?>> findById(String id) async =>
      Success(store[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(String reference) async =>
      const Success(null);

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async =>
      const Success([]);

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(
    MessageProcessingStatus status,
  ) async =>
      Success(store.values.where((m) => m.status == status).toList());

  @override

  Future<Result<int>> countByStatus(MessageProcessingStatus status) async =>

      Success(store.values.where((m) => m.status == status).length);

  @override
  Stream<int> watchCountByStatus(MessageProcessingStatus status) async* {
    yield store.values.where((m) => m.status == status).length;
  }


  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async =>
      Success(store.values.take(limit).toList());

  @override
  Future<Result<void>> updateStatus(
    String id,
    MessageProcessingStatus status,
  ) async =>
      const Success(null);

  @override
  Future<Result<void>> delete(String id) async {
    store.remove(id);
    return const Success(null);
  }
}

final class _FakeAudit implements AuditLogRepository {
  final logs = <AuditLog>[];

  @override
  Future<Result<void>> append(AuditLog log) async {
    logs.add(log);
    return const Success(null);
  }

  @override
  Future<Result<List<AuditLog>>> findByEntity(
    String entityType,
    String entityId,
  ) async =>
      Success(logs.where((l) => l.entityId == entityId).toList());
}
