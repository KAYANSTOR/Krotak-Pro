import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/application/incoming_sms_handler.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_message_recovery_service.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/platform/sms_bridge.dart';

import '../helpers/trusted_payment_source.dart';

void main() {
  group('PD-07 settings gating', () {
    test('auto-processing OFF saves and parses without calling processor', () async {
      final messages = _FakeMessages();
      final processor = _FakeProcessor();
      final settings = _FakeSettings({
        SettingKeys.smsAutoProcessingEnabled: 'false',
      });
      final handler = IncomingSmsHandler(
        bridge: SmsBridge(),
        messages: messages,
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'unused',
            amount: Money(minorUnits: 50000, currencyCode: 'YER'),
            customerIdentifier: '770123456',
            identifierType: TransferIdentifierType.phone,
            reference: 'REF-AUTO-OFF',
          ),
        ),
        processor: processor,
        ids: SequentialIdGenerator(),
        settings: settings,
        sourceGuard: trustedPaymentSourceGuard(),
      );

      final result = await handler.handleManual(
        sender: 'bank',
        body: 'تم تحويل 500 ريال الى 770123456 برقم العملية REF-AUTO-OFF',
        receivedAt: DateTime.utc(2026, 9, 12),
      );

      expect(result, isA<Success<Transaction?>>());
      expect(processor.calls, 0);
      expect(messages.store, hasLength(1));
      expect(
        messages.store.values.single.status,
        MessageProcessingStatus.parsed,
      );
    });

    test('auto-processing ON (default) invokes processor', () async {
      final messages = _FakeMessages();
      final processor = _FakeProcessor();
      final handler = IncomingSmsHandler(
        bridge: SmsBridge(),
        messages: messages,
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'unused',
            amount: Money(minorUnits: 50000, currencyCode: 'YER'),
            customerIdentifier: '770123456',
            identifierType: TransferIdentifierType.phone,
            reference: 'REF-AUTO-ON',
          ),
        ),
        processor: processor,
        ids: SequentialIdGenerator(),
        settings: _FakeSettings({}),
        sourceGuard: trustedPaymentSourceGuard(),
      );

      final result = await handler.handleManual(
        sender: 'bank',
        body: 'تم تحويل 500 ريال الى 770123456 برقم العملية REF-AUTO-ON',
        receivedAt: DateTime.utc(2026, 9, 12),
      );

      expect(result, isA<Success<Transaction?>>());
      expect(processor.calls, 1);
    });

    test('process_old_messages_on_resume OFF skips recovery', () async {
      final recovery = LocalMessageRecoveryService(
        messages: _FakeMessages()
          ..store['m1'] = IncomingMessage(
            id: 'm1',
            sender: 'bank',
            body: 'body',
            receivedAt: DateTime.utc(2026, 9, 12),
            status: MessageProcessingStatus.received,
          ),
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'm1',
            amount: Money(minorUnits: 1000, currencyCode: 'YER'),
            customerIdentifier: '770123456',
            identifierType: TransferIdentifierType.phone,
            reference: 'R1',
          ),
        ),
        processor: _FakeProcessor(),
        settings: _FakeSettings({
          SettingKeys.processOldMessagesOnResume: 'false',
        }),
        sourceGuard: trustedPaymentSourceGuard(),
      );

      final result = await recovery.recoverPending();
      expect(result, isA<Success<MessageRecoveryReport>>());
      final report = (result as Success<MessageRecoveryReport>).value;
      expect(report.skippedBySetting, isTrue);
      expect(report.attempted, 0);
    });
  });
}

final class _FakeSettings implements SettingsRepository {
  _FakeSettings(this.values);
  final Map<String, String> values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final v = values[key];
    if (v == null) return const Success(null);
    return Success(
      AppSetting(key: key, value: v, updatedAt: DateTime.utc(2026, 9, 12)),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}

final class _FakeMessages implements MessageRepository {
  final store = <String, IncomingMessage>{};
  final seenExternalReferences = <String>[];

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    store[message.id] = message;
    if (message.externalReference != null) {
      seenExternalReferences.add(message.externalReference!);
    }
    return const Success(null);
  }

  @override
  Future<Result<IncomingMessage?>> findById(String id) async =>
      Success(store[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(
    String reference,
  ) async {
    seenExternalReferences.add(reference);
    for (final m in store.values) {
      if (m.externalReference == reference) return Success(m);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async {
    final list = store.values
        .where(
          (m) =>
              m.status == MessageProcessingStatus.received ||
              m.status == MessageProcessingStatus.parsed,
        )
        .toList(growable: false);
    return Success(list);
  }

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(
    MessageProcessingStatus status,
  ) async =>
      Success(
        store.values.where((m) => m.status == status).toList(growable: false),
      );

  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async =>
      Success(store.values.take(limit).toList(growable: false));

  @override
  Future<Result<void>> updateStatus(
    String id,
    MessageProcessingStatus status,
  ) async {
    final current = store[id];
    if (current == null) {
      return const Failure(
        AppFailure(code: 'missing', message: 'missing'),
      );
    }
    store[id] = IncomingMessage(
      id: current.id,
      sender: current.sender,
      body: current.body,
      receivedAt: current.receivedAt,
      status: status,
      externalReference: current.externalReference,
    );
    return const Success(null);
  }
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

final class _FakeProcessor implements TransferProcessor {
  int calls = 0;

  @override
  Future<Result<Transaction>> process(ParsedTransfer transfer) async {
    calls++;
    return Success(
      Transaction(
        id: 'tx-$calls',
        customerId: 'customer-1',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: transfer.amount,
        createdAt: DateTime.utc(2026, 9, 12),
        reference: transfer.reference,
      ),
    );
  }
}
