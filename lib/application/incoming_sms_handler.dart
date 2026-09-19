import 'dart:async';

import '../core/id_generator.dart';
import '../core/result.dart';
import '../domain/entities/advance.dart';
import '../domain/entities/payment_event.dart';
import '../domain/entities/setting.dart';
import '../domain/entities/transaction.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/payment_source_guard.dart';
import '../domain/services/services.dart';
import '../domain/services/unified_payment_event_engine.dart';
import '../platform/sms_bridge.dart';

final class IncomingSmsHandler {
  IncomingSmsHandler({
    required this.bridge,
    required this.messages,
    required this.parser,
    required this.processor,
    required this.ids,
    required this.sourceGuard,
    this.settings,
    this.advanceService,
    this.onAfterPayment,
    UnifiedPaymentEventEngine? engine,
  }) : engine = engine ??
           UnifiedPaymentEventEngine(
             messages: messages,
             parser: parser,
             processor: processor,
             ids: ids,
             settings: settings,
             sourceGuard: sourceGuard,
           );

  final SmsBridge bridge;
  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;
  final PaymentSourceGuard sourceGuard;
  final SettingsRepository? settings;
  final AdvanceService? advanceService;
  final Future<void> Function()? onAfterPayment;
  final UnifiedPaymentEventEngine engine;
  StreamSubscription<IncomingSmsEvent>? _sub;

  void start() {
    _sub ??= bridge.incomingSms.listen(_onEvent, onError: (_) {});
    // Drain SMS captured while the UI process was not listening.
    // ignore: discarded_futures
    _drainPending();
  }

  Future<void> _drainPending() async {
    try {
      final pending = await bridge.peekPendingSms();
      if (pending.isEmpty) return;
      final acked = <String>[];
      for (final event in pending) {
        await _onEvent(event);
        final id = event.pendingId;
        if (id != null && id.isNotEmpty) acked.add(id);
      }
      await bridge.ackPendingSms(acked);
    } catch (_) {
      // Platform channel may be unavailable on non-Android; ignore.
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<Result<Transaction?>> handleManual({
    required String sender,
    required String body,
    DateTime? receivedAt,
  }) async {
    final at = receivedAt ?? DateTime.now().toUtc();
    if (_isSalafniCommand(body) &&
        advanceService != null &&
        await _salafniEnabled()) {
      final result = await advanceService!.requestByIdentifier(
        identifier: sender,
        currencyCode: await _currencyCode(),
        operationId: _salafniOperationId(sender, body, at),
      );
      if (result is Success<AdvanceIssue>) return const Success(null);
      return Failure<Transaction?>((result as Failure).error);
    }
    return engine.ingest(
      PaymentEvent(
        channel: PaymentChannel.manual,
        sourceKey: sender,
        body: body,
        receivedAt: at,
      ),
    );
  }

  Future<void> _onEvent(IncomingSmsEvent event) async {
    try {
      if (_isSalafniCommand(event.body) &&
          advanceService != null &&
          await _salafniEnabled()) {
        await advanceService!.requestByIdentifier(
          identifier: event.sender,
          currencyCode: await _currencyCode(),
          operationId: _salafniOperationId(
            event.sender,
            event.body,
            event.receivedAt,
          ),
        );
        return;
      }
      await engine.ingest(
        PaymentEvent(
          channel: PaymentChannel.sms,
          sourceKey: event.sender,
          body: event.body,
          receivedAt: event.receivedAt,
        ),
      );
    } finally {
      final hook = onAfterPayment;
      if (hook != null) {
        try {
          await hook();
        } catch (_) {}
      }
    }
  }

  bool _isSalafniCommand(String body) {
    final normalized = body
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u200f\u200e\s]+'), '');
    return normalized == 'سلفني' ||
        normalized == 'س' ||
        normalized == 's' ||
        normalized == 'salafni';
  }

  String _salafniOperationId(
    String sender,
    String body,
    DateTime receivedAt,
  ) =>
      'sms:${sender.trim().toLowerCase()}:${receivedAt.toUtc().millisecondsSinceEpoch}:${body.trim().toLowerCase()}';

  Future<bool> _salafniEnabled() async {
    if (settings == null) return false;
    final result = await settings!.find(SettingKeys.salafniEnabled);
    if (result is Failure<AppSetting?>) return false;
    final raw = (result as Success<AppSetting?>).value?.value;
    return SettingBool.read(
      raw,
      defaultValue: SettingDefaults.salafniEnabled,
    );
  }

  Future<String> _currencyCode() async {
    if (settings == null) return 'YER';
    final result = await settings!.find(SettingKeys.defaultCurrency);
    if (result is Success<AppSetting?>) {
      final value = result.value?.value.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return 'YER';
  }
}
