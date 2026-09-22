import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../rejection_codes.dart';
import '../repositories/repositories.dart';
import 'local_blocked_number_service.dart';
import 'payment_fingerprint_service.dart';
import 'payment_source_guard.dart';
import 'local_pos_balance_request_service.dart';
import 'services.dart';
import 'message_pipeline_trace.dart';

/// Single ingest path for SMS, wallet notifications, and manual entry.
///
/// Inbound commercial processing has a hard trust boundary:
/// source authorization happens BEFORE parsing/persistence, and the matched
/// template must belong to that same configured source wallet.
final class UnifiedPaymentEventEngine implements PaymentEventEngine {
  UnifiedPaymentEventEngine({
    required this.messages,
    required this.parser,
    required this.processor,
    required this.ids,
    this.settings,
    this.sourceGuard,
    this.posBalanceRequestService,
    this.metrics,
    this.fingerprints = const PaymentFingerprintService(),
  });

  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;
  final SettingsRepository? settings;
  final PaymentSourceGuard? sourceGuard;
  final LocalPosBalanceRequestService? posBalanceRequestService;
  final MessagePipelineMetrics? metrics;
  final PaymentFingerprintService fingerprints;

  @override
  Future<Result<Transaction?>> ingest(PaymentEvent event) async {
    // No guard means this is a legacy/test construction. Never permit a real
    // inbound SMS/notification to cross into parsing or persistence without an
    // explicit source trust boundary. Manual/system entry remains available.
    if (event.channel != PaymentChannel.manual && sourceGuard == null) {
      return const Failure(
        AppFailure(
          code: 'untrusted_payment_source',
          message: 'Inbound payment source is not configured',
        ),
      );
    }

    if (sourceGuard != null) {
      final sourceAuthorization = await sourceGuard!.authorize(event);
      if (sourceAuthorization is Failure<void>) {
        return Failure(sourceAuthorization.error);
      }
    }

    if (settings != null) {
      final blocked = LocalBlockedNumberService(settings: settings!);
      if (await blocked.hitsRawEvent(
        sourceKey: event.sourceKey,
        body: event.body,
      )) {
        return _rejectBlocked(event);
      }
    }

    final provisional = event.toProvisionalMessage(id: ids.next('msg'));
    final parseResult = parser.parse(provisional);
    final parsed = parseResult is Success<ParsedTransfer>
        ? parseResult.value
        : null;

    // A trusted source may only use templates linked to that same source.
    if (parsed != null && sourceGuard != null) {
      final templateAuthorization = await sourceGuard!.authorize(
        event,
        matchedTemplateId: parsed.templateId,
      );
      if (templateAuthorization is Failure<void>) {
        return Failure(templateAuthorization.error);
      }
    }

    if (parsed != null && settings != null) {
      final blocked = LocalBlockedNumberService(settings: settings!);
      if (await blocked.isBlocked(parsed.customerIdentifier)) {
        return _rejectBlocked(event);
      }
    }

    final fingerprint = fingerprints.compute(event: event, parsed: parsed);

    final existing = await messages.findByExternalReference(fingerprint.key);
    if (existing is Failure<IncomingMessage?>) {
      return Failure(existing.error);
    }
    if (existing is Success<IncomingMessage?> && existing.value != null) {
      return const Success(null);
    }

    final message = IncomingMessage(
      id: provisional.id,
      sender: event.sourceKey,
      body: provisional.body,
      receivedAt: event.receivedAt,
      status: MessageProcessingStatus.received,
      externalReference: fingerprint.key,
      customerIdentifier: parsed?.customerIdentifier,
    );

    final saveResult = await messages.save(message);
    if (saveResult is Failure<void>) {
      final raced = await messages.findByExternalReference(fingerprint.key);
      if (raced is Success<IncomingMessage?> && raced.value != null) {
        return const Success(null);
      }
      return Failure(saveResult.error);
    }

    if (parseResult is Failure<ParsedTransfer>) {
      await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
      return Failure(parseResult.error);
    }

    final parsedTransfer = parsed;
    if (parsedTransfer == null) {
      await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
      return const Failure(
        AppFailure(
          code: 'message_not_parsed',
          message: 'Inbound payment message could not be parsed',
        ),
      );
    }

    // Canonical POS card-order text is a product/order command, not a cash
    // transfer. Never let a generic financial template reinterpret it.
    final isExplicitPosOrder =
        parsedTransfer.kind == ParsedTransferKind.posCardOrder ||
        parsedTransfer.kind == ParsedTransferKind.posInstantCharge;
    if (_looksLikePosCardOrderBody(message.body) && !isExplicitPosOrder) {
      const failure = AppFailure(
        code: 'pos_order_template_required',
        message: 'رسالة طلب كروت تحتاج قالب طلب POS نشط',
      );
      await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
      return const Failure<Transaction?>(failure);
    }

    final boundParse = ParsedTransfer(
      messageId: message.id,
      amount: parsedTransfer.amount,
      customerIdentifier: parsedTransfer.customerIdentifier,
      identifierType: parsedTransfer.identifierType,
      reference: parsedTransfer.reference,
      templateId: parsedTransfer.templateId,
      posId: parsedTransfer.posId,
      rawIdentifier: parsedTransfer.rawIdentifier,
      quantity: parsedTransfer.quantity,
      deliveryOverride: parsedTransfer.deliveryOverride,
      instantCharge: parsedTransfer.instantCharge,
      kind: parsedTransfer.kind,
    );
    await messages.updateStatus(message.id, MessageProcessingStatus.parsed);
    final trace = MessagePipelineTrace(
      messageId: message.id,
      receivedAt: message.receivedAt,
    )..markParsed();

    final balanceService = posBalanceRequestService;
    if (balanceService != null &&
        parsedTransfer.amount.minorUnits == 0 &&
        parsedTransfer.reference.startsWith('balance-request:')) {
      final balanceResult = await balanceService.handle(
        message: message,
        parsed: parsedTransfer,
      );
      if (balanceResult is Failure<void>) {
        await messages.updateStatus(message.id, MessageProcessingStatus.failed);
        return Failure(balanceResult.error);
      }
      await messages.updateStatus(message.id, MessageProcessingStatus.processed);
      return const Success(null);
    }

    final auto = await _autoProcessingEnabled();
    if (!auto) {
      return const Success(null);
    }

    final processResult = await processor.process(boundParse);
    if (processResult is Success<Transaction>) {
      trace.markCommitted();
      final m = metrics;
      if (m != null) {
        // ignore: discarded_futures
        m.persist(trace);
      }
      return Success(processResult.value);
    }
    final m = metrics;
    if (m != null) {
      // ignore: discarded_futures
      m.persist(trace);
    }
    return Failure((processResult as Failure<Transaction>).error);
  }

  bool _looksLikePosCardOrderBody(String raw) {
    var normalized = raw
        .trim()
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '');
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final digits = StringBuffer();
    for (final rune in normalized.runes) {
      final ch = String.fromCharCode(rune);
      final e = eastern.indexOf(ch);
      final p = persian.indexOf(ch);
      if (e >= 0) {
        digits.write(e);
      } else if (p >= 0) {
        digits.write(p);
      } else {
        digits.write(ch);
      }
    }
    normalized = digits
        .toString()
        .replaceAll('كروت', 'كرت')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return RegExp(
      r'^\d{1,2}\s+كرت\s+\d+(?:[.,]\d{1,2})?(?:\s+\+?\d{7,15})?
    final message = IncomingMessage(
      id: ids.next('msg'),
      sender: event.sourceKey,
      body: event.body,
      receivedAt: event.receivedAt,
      status: MessageProcessingStatus.rejected,
      customerIdentifier: event.sourceKey,
    );
    await messages.save(message);
    return const Failure(
      AppFailure(
        code: RejectionCodes.blacklisted,
        message: 'Blocked number — processing skipped before parse',
      ),
    );
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
}
,
      unicode: true,
    ).hasMatch(normalized);
  }

  Future<Result<Transaction?>> _rejectBlocked(PaymentEvent event) async {
    final message = IncomingMessage(
      id: ids.next('msg'),
      sender: event.sourceKey,
      body: event.body,
      receivedAt: event.receivedAt,
      status: MessageProcessingStatus.rejected,
      customerIdentifier: event.sourceKey,
    );
    await messages.save(message);
    return const Failure(
      AppFailure(
        code: RejectionCodes.blacklisted,
        message: 'Blocked number — processing skipped before parse',
      ),
    );
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
}
