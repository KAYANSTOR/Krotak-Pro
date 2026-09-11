import 'dart:async';

import '../core/id_generator.dart';
import '../core/result.dart';
import '../domain/entities/message.dart';
import '../domain/entities/transaction.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/services.dart';
import '../platform/sms_bridge.dart';

final class IncomingSmsHandler {
  IncomingSmsHandler({
    required this.bridge,
    required this.messages,
    required this.parser,
    required this.processor,
    required this.ids,
  });

  final SmsBridge bridge;
  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;

  StreamSubscription<IncomingSmsEvent>? _sub;

  void start() {
    _sub ??= bridge.incomingSms.listen(_onEvent, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<Result<Transaction?>> handleManual({
    required String sender,
    required String body,
    DateTime? receivedAt,
  }) {
    return _process(
      IncomingSmsEvent(
        sender: sender,
        body: body,
        timestampMillis:
            (receivedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _onEvent(IncomingSmsEvent event) async {
    await _process(event);
  }

  Future<Result<Transaction?>> _process(IncomingSmsEvent event) async {
    final dedupeKey = _dedupeKey(event);
    final existing = await messages.findByExternalReference(dedupeKey);
    if (existing is Success<IncomingMessage?> && existing.value != null) {
      return const Success(null);
    }

    final messageId = ids.next('msg');
    final message = IncomingMessage(
      id: messageId,
      sender: event.sender,
      body: event.body,
      receivedAt: event.receivedAt,
      status: MessageProcessingStatus.received,
      externalReference: dedupeKey,
    );

    final saveResult = await messages.save(message);
    if (saveResult is Failure<void>) {
      return Failure(saveResult.error);
    }

    final parseResult = parser.parse(message);
    if (parseResult is Failure<ParsedTransfer>) {
      await messages.updateStatus(messageId, MessageProcessingStatus.rejected);
      return Failure(parseResult.error);
    }

    final parsed = (parseResult as Success<ParsedTransfer>).value;
    await messages.updateStatus(messageId, MessageProcessingStatus.parsed);

    final processResult = await processor.process(parsed);
    if (processResult is Success<Transaction>) {
      return Success(processResult.value);
    }
    return Failure((processResult as Failure<Transaction>).error);
  }

  String _dedupeKey(IncomingSmsEvent event) {
    final minute = event.timestampMillis ~/ 60000;
    final bodyKey = event.body.hashCode.toRadixString(16);
    return '${event.sender}|$bodyKey|$minute';
  }
}
