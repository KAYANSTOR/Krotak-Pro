import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/payment_event.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/payment_fingerprint_service.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/domain/services/unified_payment_event_engine.dart';

void main() {
  group('PaymentFingerprintService', () {
    const service = PaymentFingerprintService();

    test('same wallet reference from SMS and notification share one key', () {
      const parsed = ParsedTransfer(
        messageId: 'm',
        amount: Money(minorUnits: 1000, currencyCode: 'YER'),
        customerIdentifier: '770123456',
        identifierType: TransferIdentifierType.phone,
        reference: 'OP-99',
      );
      final sms = service.compute(
        event: PaymentEvent(
          channel: PaymentChannel.sms,
          sourceKey: 'JIB',
          body: 'sms body OP-99',
          receivedAt: DateTime.utc(2026, 9, 13),
        ),
        parsed: parsed,
      );
      final note = service.compute(
        event: PaymentEvent(
          channel: PaymentChannel.notification,
          sourceKey: 'JIB',
          body: 'notification title OP-99',
          receivedAt: DateTime.utc(2026, 9, 13, 0, 1),
          packageName: 'com.wallet.jib',
        ),
        parsed: parsed,
      );
      expect(sms.key, note.key);
      expect(sms.strategy, 'reference');
      expect(sms.key, 'pay:v1:ref:JIB:OP-99');
    });

    test('falls back to amount + identity + body when no reference', () {
      const parsed = ParsedTransfer(
        messageId: 'm',
        amount: Money(minorUnits: 2500, currencyCode: 'YER'),
        customerIdentifier: '770000111',
        identifierType: TransferIdentifierType.phone,
        reference: '',
      );
      final fp = service.compute(
        event: PaymentEvent(
          channel: PaymentChannel.sms,
          sourceKey: '  bank  ',
          body: '  paid 25  ',
          receivedAt: DateTime.utc(2026, 9, 13),
        ),
        parsed: parsed,
      );
      expect(fp.strategy, 'amount_identity_body');
      expect(fp.key, contains('pay:v1:amt:bank:YER:2500:770000111:paid 25'));
    });
  });

  group('UnifiedPaymentEventEngine', () {
    test('persists, parses and processes a new event', () async {
      final messages = _FakeMessages();
      final processor = _FakeProcessor();
      final engine = UnifiedPaymentEventEngine(
        messages: messages,
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'unused',
            amount: Money(minorUnits: 50000, currencyCode: 'YER'),
            customerIdentifier: '770123456',
            identifierType: TransferIdentifierType.phone,
            reference: 'REF-1',
          ),
        ),
        processor: processor,
        ids: SequentialIdGenerator(),
        settings: _FakeSettings({}),
      );

      final result = await engine.ingest(
        PaymentEvent(
          channel: PaymentChannel.sms,
          sourceKey: 'bank',
          body: 'transfer REF-1',
          receivedAt: DateTime.utc(2026, 9, 13),
        ),
      );

      expect(result, isA<Success<Transaction?>>());
      expect(processor.calls, 1);
      expect(messages.store, hasLength(1));
      expect(
        messages.store.values.single.externalReference,
        'pay:v1:ref:bank:REF-1',
      );
    });

    test('SMS then notification with same ref is a no-op duplicate', () async {
      final messages = _FakeMessages();
      final processor = _FakeProcessor();
      final engine = UnifiedPaymentEventEngine(
        messages: messages,
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'unused',
            amount: Money(minorUnits: 50000, currencyCode: 'YER'),
            customerIdentifier: '770123456',
            identifierType: TransferIdentifierType.phone,
            reference: 'REF-DUP',
          ),
        ),
        processor: processor,
        ids: SequentialIdGenerator(),
      );

      await engine.ingest(
        PaymentEvent(
          channel: PaymentChannel.sms,
          sourceKey: 'JIB',
          body: 'sms REF-DUP',
          receivedAt: DateTime.utc(2026, 9, 13),
        ),
      );
      final second = await engine.ingest(
        PaymentEvent(
          channel: PaymentChannel.notification,
          sourceKey: 'JIB',
          body: 'push REF-DUP',
          receivedAt: DateTime.utc(2026, 9, 13, 0, 2),
          packageName: 'com.wallet.jib',
        ),
      );

      expect(second, isA<Success<Transaction?>>());
      expect((second as Success<Transaction?>).value, isNull);
      expect(processor.calls, 1);
      expect(messages.store, hasLength(1));
    });

    test('auto-processing off stops after parse', () async {
      final messages = _FakeMessages();
      final processor = _FakeProcessor();
      final engine = UnifiedPaymentEventEngine(
        messages: messages,
        parser: _FakeParser(
          const ParsedTransfer(
            messageId: 'unused',
            amount: Money(minorUnits: 1000, currencyCode: 'YER'),
            customerIdentifier: '770123456',
            identifierType: TransferIdentifierType.phone,
            reference: 'REF-OFF',
          ),
        ),
        processor: processor,
        ids: SequentialIdGenerator(),
        settings: _FakeSettings({
          SettingKeys.smsAutoProcessingEnabled: 'false',
        }),
      );

      await engine.ingest(
        PaymentEvent(
          channel: PaymentChannel.sms,
          sourceKey: 'bank',
          body: 'REF-OFF',
          receivedAt: DateTime.utc(2026, 9, 13),
        ),
      );

      expect(processor.calls, 0);
      expect(
        messages.store.values.single.status,
        MessageProcessingStatus.parsed,
      );
    });

    test('unparsed event is rejected and not processed', () async {
      final messages = _FakeMessages();
      final processor = _FakeProcessor();
      final engine = UnifiedPaymentEventEngine(
        messages: messages,
        parser: _FailingParser(),
        processor: processor,
        ids: SequentialIdGenerator(),
      );

      final result = await engine.ingest(
        PaymentEvent(
          channel: PaymentChannel.sms,
          sourceKey: 'bank',
          body: 'garbage',
          receivedAt: DateTime.utc(2026, 9, 13),
        ),
      );

      expect(result, isA<Failure<Transaction?>>());
      expect(processor.calls, 0);
      expect(
        messages.store.values.single.status,
        MessageProcessingStatus.rejected,
      );
    });
  });
}

final class _FakeParser implements MessageParser {
  _FakeParser(this.parsed);
  final ParsedTransfer parsed;

  @override
  Result<ParsedTransfer> parse(IncomingMessage message) {
    return Success(
      ParsedTransfer(
        messageId: message.id,
        amount: parsed.amount,
        customerIdentifier: parsed.customerIdentifier,
        identifierType: parsed.identifierType,
        reference: parsed.reference,
        templateId: parsed.templateId,
        rawIdentifier: parsed.rawIdentifier,
      ),
    );
  }
}

final class _FailingParser implements MessageParser {
  @override
  Result<ParsedTransfer> parse(IncomingMessage message) {
    return const Failure(
      AppFailure(code: 'unparsed', message: 'no template'),
    );
  }
}

final class _FakeProcessor implements TransferProcessor {
  int calls = 0;

  @override
  Future<Result<Transaction>> process(ParsedTransfer transfer) async {
    calls += 1;
    return Success(
      Transaction(
        id: 'tx-${transfer.messageId}',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: transfer.amount,
        createdAt: DateTime.utc(2026, 9, 13),
        customerId: 'c1',
        reference: transfer.reference,
      ),
    );
  }
}

final class _FakeMessages implements MessageRepository {
  final store = <String, IncomingMessage>{};

  @override
  Future<Result<IncomingMessage?>> findById(String id) async =>
      Success(store[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(
    String reference,
  ) async {
    for (final m in store.values) {
      if (m.externalReference == reference) return Success(m);
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    store[message.id] = message;
    return const Success(null);
  }

  @override
  Future<Result<void>> updateStatus(
    String id,
    MessageProcessingStatus status,
  ) async {
    final current = store[id];
    if (current == null) {
      return const Failure(AppFailure(code: 'missing', message: 'missing'));
    }
    store[id] = IncomingMessage(
      id: current.id,
      sender: current.sender,
      body: current.body,
      receivedAt: current.receivedAt,
      status: status,
      externalReference: current.externalReference,
      customerIdentifier: current.customerIdentifier,
    );
    return const Success(null);
  }

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(
    MessageProcessingStatus status,
  ) async {
    return Success(store.values.where((m) => m.status == status).toList());
  }

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async {
    return Success(
      store.values
          .where(
            (m) =>
                m.status == MessageProcessingStatus.received ||
                m.status == MessageProcessingStatus.parsed,
          )
          .toList(),
    );
  }

  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async {
    return Success(store.values.take(limit).toList());
  }
}

final class _FakeSettings implements SettingsRepository {
  _FakeSettings(this.values);
  final Map<String, String> values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = values[key];
    if (value == null) return const Success(null);
    return Success(
      AppSetting(key: key, value: value, updatedAt: DateTime.utc(2026, 9, 13)),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}
