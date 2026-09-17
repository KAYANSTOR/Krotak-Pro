import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/payment_event.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_message_parser.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';
import 'package:net_app/domain/services/payment_source_guard.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/domain/services/unified_payment_event_engine.dart';

void main() {
  late _Settings settings;
  late _Messages messages;
  late _Processor processor;
  late Wallet wallet;

  setUp(() {
    settings = _Settings();
    messages = _Messages();
    processor = _Processor();
    wallet = Wallet(
      id: 'wallet-1',
      name: 'Test Wallet',
      status: WalletStatus.active,
      createdAt: DateTime.utc(2026, 9, 18),
      senderId: 'BANK',
      sourceMode: WalletSourceMode.sms,
    );
  });

  UnifiedPaymentEventEngine buildEngine({
    required List<TransferTemplate> templates,
    List<PosAccount> posAccounts = const [],
  }) {
    settings.values[SettingKeys.posAccounts] = jsonEncode(
      posAccounts.map((account) => account.toJson()).toList(),
    );
    final parser = LocalMessageParser(templates: templates);
    final posRegistry = LocalPosAccountRegistry(
      settings: settings,
      clock: FixedClock(DateTime.utc(2026, 9, 18)),
    );
    final guard = PaymentSourceGuard(
      wallets: _WalletRepo([wallet]),
      templates: _Templates(templates),
      posRegistry: posRegistry,
    );
    return UnifiedPaymentEventEngine(
      messages: messages,
      parser: parser,
      processor: processor,
      ids: SequentialIdGenerator(),
      settings: settings,
      sourceGuard: guard,
    );
  }

  TransferTemplate template({
    required String id,
    required String pattern,
    String? posAccountId,
  }) {
    return TransferTemplate(
      id: id,
      name: id,
      pattern: pattern,
      isActive: true,
      walletId: wallet.id,
      posAccountId: posAccountId,
    );
  }

  PaymentEvent event(String body) => PaymentEvent(
        channel: PaymentChannel.sms,
        sourceKey: wallet.senderId!,
        body: body,
        receivedAt: DateTime.utc(2026, 9, 18, 10),
      );

  test('matching active POS message uses only that POS template', () async {
    final engine = buildEngine(
      posAccounts: const [
        PosAccount(
          posId: 'pos-1',
          customerId: 'customer-1',
          name: 'POS One',
          identifiers: ['777123456'],
        ),
      ],
      templates: [
        template(
          id: 'pos-1-template',
          posAccountId: 'pos-1',
          pattern: 'POS1 {amount} {phone} {ref}',
        ),
        template(
          id: 'pos-2-template',
          posAccountId: 'pos-2',
          pattern: 'POS2 {amount} {phone} {ref}',
        ),
        template(
          id: 'generic',
          pattern: 'GENERIC {amount} {phone} {ref}',
        ),
      ],
    );

    final result = await engine.ingest(
      event('POS1 10 777123456 REF-1'),
    );

    expect(result, isA<Success<Transaction?>>());
    expect(processor.calls, 1);
    expect(messages.store, hasLength(1));
  });

  test('non-matching message from active POS is silently ignored', () async {
    final engine = buildEngine(
      posAccounts: const [
        PosAccount(
          posId: 'pos-1',
          customerId: 'customer-1',
          name: 'POS One',
          identifiers: ['777123456'],
        ),
      ],
      templates: [
        template(
          id: 'pos-1-template',
          posAccountId: 'pos-1',
          pattern: 'POS1 {amount} {phone} {ref}',
        ),
      ],
    );

    final result = await engine.ingest(
      event('UNRELATED 10 777123456 REF-2'),
    );

    expect(result, isA<Success<Transaction?>>());
    expect((result as Success<Transaction?>).value, isNull);
    expect(processor.calls, 0);
    expect(messages.store, isEmpty);
  });

  test('generic wallet template cannot capture a POS message', () async {
    final engine = buildEngine(
      posAccounts: const [
        PosAccount(
          posId: 'pos-1',
          customerId: 'customer-1',
          name: 'POS One',
          identifiers: ['777123456'],
        ),
      ],
      templates: [
        template(
          id: 'generic',
          pattern: 'GENERIC {amount} {phone} {ref}',
        ),
      ],
    );

    final result = await engine.ingest(
      event('GENERIC 10 777123456 REF-3'),
    );

    expect(result, isA<Success<Transaction?>>());
    expect((result as Success<Transaction?>).value, isNull);
    expect(processor.calls, 0);
    expect(messages.store, isEmpty);
  });

  test('template belonging to another POS cannot capture this POS message', () async {
    final engine = buildEngine(
      posAccounts: const [
        PosAccount(
          posId: 'pos-1',
          customerId: 'customer-1',
          name: 'POS One',
          identifiers: ['777123456'],
        ),
      ],
      templates: [
        template(
          id: 'pos-2-template',
          posAccountId: 'pos-2',
          pattern: 'POS2 {amount} {phone} {ref}',
        ),
      ],
    );

    final result = await engine.ingest(
      event('POS2 10 777123456 REF-4'),
    );

    expect(result, isA<Success<Transaction?>>());
    expect((result as Success<Transaction?>).value, isNull);
    expect(processor.calls, 0);
    expect(messages.store, isEmpty);
  });

  test('message without a POS account can use wallet-general template', () async {
    final engine = buildEngine(
      templates: [
        template(
          id: 'generic',
          pattern: 'GENERIC {amount} {phone} {ref}',
        ),
      ],
    );

    final result = await engine.ingest(
      event('GENERIC 10 778888888 REF-5'),
    );

    expect(result, isA<Success<Transaction?>>());
    expect(processor.calls, 1);
    expect(messages.store, hasLength(1));
  });

  test('ambiguous active POS identifier fails closed before persistence', () async {
    final engine = buildEngine(
      posAccounts: const [
        PosAccount(
          posId: 'pos-1',
          customerId: 'customer-1',
          name: 'POS One',
          identifiers: ['777123456'],
        ),
        PosAccount(
          posId: 'pos-2',
          customerId: 'customer-2',
          name: 'POS Two',
          identifiers: ['777123456'],
        ),
      ],
      templates: [
        template(
          id: 'pos-1-template',
          posAccountId: 'pos-1',
          pattern: 'POS1 {amount} {phone} {ref}',
        ),
        template(
          id: 'pos-2-template',
          posAccountId: 'pos-2',
          pattern: 'POS2 {amount} {phone} {ref}',
        ),
      ],
    );

    final result = await engine.ingest(
      event('POS1 10 777123456 REF-6'),
    );

    expect(result, isA<Failure<Transaction?>>());
    expect((result as Failure<Transaction?>).error.code, 'pos_identifier_ambiguous');
    expect(processor.calls, 0);
    expect(messages.store, isEmpty);
  });
}

final class _Settings implements SettingsRepository {
  final Map<String, String> values = <String, String>{};

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = values[key];
    if (value == null) return const Success(null);
    return Success(
      AppSetting(
        key: key,
        value: value,
        updatedAt: DateTime.utc(2026, 9, 18),
      ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}

final class _WalletRepo implements WalletRepository {
  _WalletRepo(this.items);
  final List<Wallet> items;

  @override
  Future<Result<Wallet?>> findById(String id) async {
    for (final item in items) {
      if (item.id == id) return Success(item);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<Wallet>>> listAll() async => Success(items);

  @override
  Future<Result<void>> save(Wallet wallet) async => const Success(null);
}

final class _Templates implements TransferTemplateRepository {
  _Templates(this.items);
  final List<TransferTemplate> items;

  @override
  Future<Result<void>> delete(String id) async => const Success(null);

  @override
  Future<Result<TransferTemplate?>> findById(String id) async {
    for (final item in items) {
      if (item.id == id) return Success(item);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<TransferTemplate>>> listAll() async => Success(items);

  @override
  Future<Result<List<TransferTemplate>>> listByWallet(String? walletId) async =>
      Success(items.where((item) => item.walletId == walletId).toList());

  @override
  Future<Result<void>> save(TransferTemplate value) async => const Success(null);
}

// Contract guard: this fake intentionally implements the current delete API.
final class _Messages implements MessageRepository {
  final Map<String, IncomingMessage> store = <String, IncomingMessage>{};

  @override
  Future<Result<IncomingMessage?>> findById(String id) async => Success(store[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(String reference) async {
    for (final message in store.values) {
      if (message.externalReference == reference) return Success(message);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(
    MessageProcessingStatus status,
  ) async =>
      Success(store.values.where((message) => message.status == status).toList());

  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async =>
      Success(store.values.take(limit).toList());

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async => Success(
        store.values
            .where(
              (message) =>
                  message.status == MessageProcessingStatus.received ||
                  message.status == MessageProcessingStatus.parsed,
            )
            .toList(),
      );

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
      return const Failure(
        AppFailure(code: 'message_not_found', message: 'missing message'),
      );
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
}

final class _Processor implements TransferProcessor {
  int calls = 0;

  @override
  Future<Result<Transaction>> process(ParsedTransfer transfer) async {
    calls++;
    return Success(
      Transaction(
        id: 'tx-$calls',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: transfer.amount,
        createdAt: DateTime.utc(2026, 9, 18),
        customerId: 'customer-1',
        reference: transfer.reference,
      ),
    );
  }
}
