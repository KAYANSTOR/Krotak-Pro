import 'dart:async';

import '../core/id_generator.dart';
import '../core/result.dart';
import '../domain/entities/payment_event.dart';
import '../domain/entities/setting.dart';
import '../domain/entities/transaction.dart';
import '../domain/repositories/repositories.dart';
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
    this.settings,
    this.advanceService,
    UnifiedPaymentEventEngine? engine,
  }) : engine = engine ?? UnifiedPaymentEventEngine(messages: messages, parser: parser, processor: processor, ids: ids, settings: settings);

  final SmsBridge bridge;
  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;
  final SettingsRepository? settings;
  final AdvanceService? advanceService;
  final UnifiedPaymentEventEngine engine;

  StreamSubscription<IncomingSmsEvent>? _sub;

  void start() { _sub ??= bridge.incomingSms.listen(_onEvent, onError: (_) {}); }

  void stop() { _sub?.cancel(); _sub = null; }

  Future<Result<Transaction?>> handleManual({required String sender, required String body, DateTime? receivedAt}) async {
    if (_isSalafniCommand(body) && advanceService != null) {
      final enabled = await _salafniEnabled();
      if (enabled) {
        final result = await advanceService!.requestByIdentifier(
          identifier: sender,
          currencyCode: await _currencyCode(),
          operationId: _salafniOperationId(sender, body),
        );
        if (result is Success<AdvanceIssue>) return const Success(null);
        return Failure((result as Failure).error);
      }
    }
    return engine.ingest(PaymentEvent(channel: PaymentChannel.manual, sourceKey: sender, body: body, receivedAt: receivedAt ?? DateTime.now().toUtc()));
  }

  Future<void> _onEvent(IncomingSmsEvent event) async {
    if (_isSalafniCommand(event.body) && advanceService != null && await _salafniEnabled()) {
      await advanceService!.requestByIdentifier(
        identifier: event.sender,
        currencyCode: await _currencyCode(),
        operationId: _salafniOperationId(event.sender, event.body),
      );
      return;
    }
    await engine.ingest(PaymentEvent(channel: PaymentChannel.sms, sourceKey: event.sender, body: event.body, receivedAt: event.receivedAt));
  }

  bool _isSalafniCommand(String body) {
    final normalized = body.trim().toLowerCase().replaceAll(RegExp(r'[\u200f\u200e\s]+'), '');
    return normalized == 'سلفني' || normalized == 'س' || normalized == 's' || normalized == 'salafni';
  }

  String _salafniOperationId(String sender, String body) => 'sms:${sender.trim().toLowerCase()}:${body.trim().toLowerCase()}';

  Future<bool> _salafniEnabled() async {
    if (settings == null) return false;
    final result = await settings!.find(SettingKeys.salafniEnabled);
    if (result is Failure<AppSetting?>) return false;
    final raw = (result as Success<AppSetting?>).value?.value;
    return SettingBool.read(raw, defaultValue: SettingDefaults.salafniEnabled);
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
