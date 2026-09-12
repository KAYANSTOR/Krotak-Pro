import 'dart:async';

import '../core/id_generator.dart';
import '../core/result.dart';
import '../domain/entities/message.dart';
import '../domain/entities/setting.dart';
import '../domain/entities/transaction.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/services.dart';
import '../platform/sms_bridge.dart';

/// Wires platform SMS events → persist → parse → (optional) process transfer.
///
/// PD-07 gates:
/// - [SettingKeys.smsAutoProcessingEnabled] false → save + parse only; no
///   commercial credit / reserve / send. Message stays [MessageProcessingStatus.parsed].
final class IncomingSmsHandler {
  IncomingSmsHandler({
    required this.bridge,
    required this.messages,
    required this.parser,
    required this.processor,
    required this.ids,
    this.settings,
  });

  final SmsBridge bridge;
  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;
  final SettingsRepository? settings;

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
    final provisional = IncomingMessage(
      id: ids.next('msg'),
      sender: event.sender,
      body: event.body,
      receivedAt: event.receivedAt,
      status: MessageProcessingStatus.received,
    );

    // Parse before persistence so an available bank/reference operation id can
    // become the stable dedupe key. Malformed messages fall back to a canonical
    // sender/body key; neither path depends on a process-local hashCode or time.
    final parseResult = parser.parse(provisional);
    final dedupeKey = _dedupeKey(event, parseResult);

    final existing = await messages.findByExternalReference(dedupeKey);
    if (existing is Success<IncomingMessage?> && existing.value != null) {
      return const Success(null);
    }
    if (existing is Failure<IncomingMessage?>) {
      return Failure(existing.error);
    }

    final message = IncomingMessage(
      id: provisional.id,
      sender: event.sender,
      body: event.body,
      receivedAt: event.receivedAt,
      status: MessageProcessingStatus.received,
      externalReference: dedupeKey,
    );

    final saveResult = await messages.save(message);
    if (saveResult is Failure<void>) {
      // The DB has a unique index on external_reference. Another handler may
      // have won the race between lookup and insert; treat that as idempotent.
      final raced = await messages.findByExternalReference(dedupeKey);
      if (raced is Success<IncomingMessage?> && raced.value != null) {
        return const Success(null);
      }
      return Failure(saveResult.error);
    }

    if (parseResult is Failure<ParsedTransfer>) {
      await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
      return Failure(parseResult.error);
    }

    final parsed = (parseResult as Success<ParsedTransfer>).value;
    await messages.updateStatus(message.id, MessageProcessingStatus.parsed);

    // PD-07 Q3: auto-processing off → keep message for later recovery / manual.
    final auto = await _autoProcessingEnabled();
    if (!auto) {
      return const Success(null);
    }

    final processResult = await processor.process(parsed);
    if (processResult is Success<Transaction>) {
      return Success(processResult.value);
    }
    return Failure((processResult as Failure<Transaction>).error);
  }

  Future<bool> _autoProcessingEnabled() async {
    final s = settings;
    if (s == null) return SettingDefaults.smsAutoProcessingEnabled;
    final result = await s.find(SettingKeys.smsAutoProcessingEnabled);
    if (result is! Success<AppSetting?>) {
      return SettingDefaults.smsAutoProcessingEnabled;
    }
    return SettingBool.read(
      result.value?.value,
      defaultValue: SettingDefaults.smsAutoProcessingEnabled,
    );
  }

  String _dedupeKey(
    IncomingSmsEvent event,
    Result<ParsedTransfer> parseResult,
  ) {
    final sender = _canonicalize(event.sender);
    if (parseResult is Success<ParsedTransfer>) {
      final reference = _canonicalize(parseResult.value.reference);
      if (reference.isNotEmpty) {
        return 'sms:v2:ref:$sender:$reference';
      }
    }

    final body = _canonicalize(event.body);
    return 'sms:v2:body:$sender:$body';
  }

  String _canonicalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
