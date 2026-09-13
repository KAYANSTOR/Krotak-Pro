import 'dart:async';

import '../core/id_generator.dart';
import '../core/result.dart';
import '../domain/entities/payment_event.dart';
import '../domain/entities/transaction.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/services.dart';
import '../domain/services/unified_payment_event_engine.dart';
import '../platform/sms_bridge.dart';

/// Wires platform SMS events into [UnifiedPaymentEventEngine].
///
/// PD-07 gates remain inside the engine (auto-processing).
final class IncomingSmsHandler {
  IncomingSmsHandler({
    required this.bridge,
    required this.messages,
    required this.parser,
    required this.processor,
    required this.ids,
    this.settings,
    UnifiedPaymentEventEngine? engine,
  }) : engine = engine ??
            UnifiedPaymentEventEngine(
              messages: messages,
              parser: parser,
              processor: processor,
              ids: ids,
              settings: settings,
            );

  final SmsBridge bridge;
  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;
  final SettingsRepository? settings;
  final UnifiedPaymentEventEngine engine;

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
    return engine.ingest(
      PaymentEvent(
        channel: PaymentChannel.manual,
        sourceKey: sender,
        body: body,
        receivedAt: receivedAt ?? DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _onEvent(IncomingSmsEvent event) async {
    await engine.ingest(
      PaymentEvent(
        channel: PaymentChannel.sms,
        sourceKey: event.sender,
        body: event.body,
        receivedAt: event.receivedAt,
      ),
    );
  }
}
