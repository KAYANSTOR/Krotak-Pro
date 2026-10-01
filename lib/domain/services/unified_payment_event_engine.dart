import 'dart:convert';

import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
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
import 'template_performance_service.dart';

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
    this.templatePerformance,
    this.auditLogs,
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
  final TemplatePerformanceService? templatePerformance;
  final AuditLogRepository? auditLogs;
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

    PaymentSourceDiagnosis? sourceDiagnosis;
    if (sourceGuard != null) {
      final diagnosisResult = await sourceGuard!.diagnose(event);
      if (diagnosisResult is Failure<PaymentSourceDiagnosis>) {
        return Failure(diagnosisResult.error);
      }
      sourceDiagnosis = (diagnosisResult as Success<PaymentSourceDiagnosis>).value;
      if (!sourceDiagnosis!.authorized) {
        return _rejectUnauthorized(
          event,
          AppFailure(
            code: sourceDiagnosis!.failureCode ?? RejectionCodes.other,
            message: sourceDiagnosis!.failureMessage ?? 'Payment source rejected',
          ),
          diagnosis: sourceDiagnosis,
        );
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
    final parseResult = _parseForAuthorizedSource(provisional, sourceDiagnosis?.activeTemplateIds.toSet());
    final parsed = parseResult is Success<ParsedTransfer>
        ? parseResult.value
        : null;

    if (parsed != null && sourceGuard != null) {
      final templateDiagnosis = await sourceGuard!.diagnose(
        event,
        matchedTemplateId: parsed.templateId,
      );
      if (templateDiagnosis is Failure<PaymentSourceDiagnosis>) {
        return Failure(templateDiagnosis.error);
      }
      sourceDiagnosis =
          (templateDiagnosis as Success<PaymentSourceDiagnosis>).value;
      if (!sourceDiagnosis!.authorized) {
        return _rejectUnauthorized(
          event,
          AppFailure(
            code: sourceDiagnosis!.failureCode ?? RejectionCodes.other,
            message: sourceDiagnosis!.failureMessage ?? 'Payment source rejected',
          ),
          diagnosis: sourceDiagnosis,
        );
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
      await templatePerformance?.recordUnmatched();
      await _persistPipelineDiagnostic(
        event: event,
        messageId: message.id,
        stage: 'parser',
        diagnosis: sourceDiagnosis,
        failure: parseResult.error,
      );
      return Failure(parseResult.error);
    }

    final parsedTransfer = parsed;
    if (parsedTransfer == null) {
      await messages.updateStatus(message.id, MessageProcessingStatus.rejected);
      await templatePerformance?.recordUnmatched();
      const failure = const AppFailure(
        code: 'message_not_parsed',
        message: 'Inbound payment message could not be parsed',
      );
      await _persistPipelineDiagnostic(
        event: event,
        messageId: message.id,
        stage: 'parser',
        diagnosis: sourceDiagnosis,
        failure: failure,
      );
      return Failure(failure);
    }

    await templatePerformance?.recordMatch(parsedTransfer.templateId ?? '');

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
    );
    await messages.updateStatus(message.id, MessageProcessingStatus.parsed);
    await _persistPipelineDiagnostic(
      event: event,
      messageId: message.id,
      stage: 'parsed',
      diagnosis: sourceDiagnosis,
      parsed: boundParse,
    );
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
        await _persistPipelineDiagnostic(
          event: event,
          messageId: message.id,
          stage: 'balance_request_processor',
          diagnosis: sourceDiagnosis,
          parsed: boundParse,
          failure: balanceResult.error,
        );
        return Failure(balanceResult.error);
      }
      await messages.updateStatus(message.id, MessageProcessingStatus.processed);
      await _persistPipelineDiagnostic(
        event: event,
        messageId: message.id,
        stage: 'processed',
        diagnosis: sourceDiagnosis,
        parsed: boundParse,
      );
      return const Success(null);
    }

    final auto = await _autoProcessingEnabled();
    if (!auto) {
      await _persistPipelineDiagnostic(
        event: event,
        messageId: message.id,
        stage: 'pending_auto_processing_disabled',
        diagnosis: sourceDiagnosis,
        parsed: boundParse,
      );
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
      await _persistPipelineDiagnostic(
        event: event,
        messageId: message.id,
        stage: 'processed',
        diagnosis: sourceDiagnosis,
        parsed: boundParse,
      );
      return Success(processResult.value);
    }
    final m = metrics;
    if (m != null) {
      // ignore: discarded_futures
      m.persist(trace);
    }
    final failure = (processResult as Failure<Transaction>).error;
    await _markFailedIfStillParsed(message.id);
    await _persistPipelineDiagnostic(
      event: event,
      messageId: message.id,
      stage: 'processor',
      diagnosis: sourceDiagnosis,
      parsed: boundParse,
      failure: failure,
    );
    return Failure(failure);
  }

  Result<ParsedTransfer> _parseForAuthorizedSource(
    IncomingMessage message,
    Set<String>? templateIds,
  ) {
    if (templateIds == null) return parser.parse(message);
    final scopedParser = parser;
    if (scopedParser is SourceScopedMessageParser) {
      return scopedParser.parseForSource(
        message,
        templateIds: templateIds,
      );
    }
    return parser.parse(message);
  }

  Future<void> _markFailedIfStillParsed(String messageId) async {
    try {
      final current = await messages.findById(messageId);
      if (current is Success<IncomingMessage?> &&
          current.value?.status == MessageProcessingStatus.parsed) {
        await messages.updateStatus(messageId, MessageProcessingStatus.failed);
      }
    } catch (_) {}
  }

  Future<void> _persistPipelineDiagnostic({
    required PaymentEvent event,
    required String messageId,
    required String stage,
    PaymentSourceDiagnosis? diagnosis,
    ParsedTransfer? parsed,
    AppFailure? failure,
  }) async {
    final logs = auditLogs;
    if (logs == null) return;
    try {
      await logs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: messageId,
          action: 'pipeline_diagnostic',
          occurredAt: event.receivedAt,
          payloadJson: jsonEncode({
            'stage': stage,
            'messageId': messageId,
            'channel': event.channel.name,
            'rawSource': event.sourceKey,
            'normalizedSource': event.sourceKey
                .trim()
                .replaceAll(RegExp(r'\s+'), '')
                .toLowerCase(),
            'packageName': event.packageName,
            'source': diagnosis?.toJson(),
            'parser': parsed == null
                ? null
                : {
                    'templateId': parsed.templateId,
                    'amountMinorUnits': parsed.amount.minorUnits,
                    'currency': parsed.amount.currencyCode,
                    'customerIdentifier': parsed.customerIdentifier,
                    'identifierType': parsed.identifierType.name,
                    'reference': parsed.reference,
                    'posId': parsed.posId,
                    'quantity': parsed.quantity,
                  },
            'processorResult': failure == null ? 'success_or_pending' : 'failure',
            'failureCode': failure?.code,
            'reason': failure?.message,
          }),
        ),
      );
    } catch (_) {}
  }

  /// يحفظ رسالة **مرفوضة** عندما تفشل حدود الثقة في المصدر لسبب **يخص مصدراً
  /// أنشأه المشغّل بنفسه** (نقطة بيع نشطة بلا قالب مرتبط، قالب لا يخص
  /// المصدر) — هذه حالات تشخيصية مفيدة، فتُحفظ ليراها المشغّل ويصلحها.
  ///
  /// أما حين يكون السبب `RejectionCodes.unknownSender` — أي أن المُرسل لا
  /// يطابق أي محفظة نشطة ولا أي نقطة بيع نشطة مضافة في النظام أصلاً — فهذه
  /// رسالة من جهة خارج نطاق النظام تماماً (رسالة شخصية، رمز تحقق، إلخ)،
  /// ولا تُحفظ ولا يُسجَّل لها أي أثر: لا صف في قاعدة البيانات ولا سجل
  /// تدقيق ولا ظهور في أي شاشة. هذا هو الحد الفاصل بين «مصدر معروف لديك
  /// لكنه معطّل الآن» (يُحفظ) و«مصدر لا علاقة له بنظامك إطلاقاً» (يُتجاهل).
  Future<Result<Transaction?>> _rejectUnauthorized(
    PaymentEvent event,
    AppFailure failure, {
    PaymentSourceDiagnosis? diagnosis,
  }) async {
    if (failure.code == RejectionCodes.unknownSender) {
      return Failure(failure);
    }

    final provisional = event.toProvisionalMessage(id: ids.next('msg'));
    final fingerprint = fingerprints.compute(event: event, parsed: null);
    final existing = await messages.findByExternalReference(fingerprint.key);
    if (existing is Success<IncomingMessage?> && existing.value != null) {
      return Failure(failure);
    }

    await messages.save(
      IncomingMessage(
        id: provisional.id,
        sender: event.sourceKey,
        body: provisional.body,
        receivedAt: event.receivedAt,
        status: MessageProcessingStatus.rejected,
        externalReference: fingerprint.key,
      ),
    );

    final audit = auditLogs;
    if (audit != null) {
      await audit.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: provisional.id,
          action: failure.code,
          occurredAt: event.receivedAt,
          payloadJson: jsonEncode({
            'code': failure.code,
            'reason': failure.message,
            'messageId': provisional.id,
            'channel': event.channel.name,
            'source': diagnosis?.toJson(),
          }),
        ),
      );
    }

    await _persistPipelineDiagnostic(
      event: event,
      messageId: provisional.id,
      stage: 'source_guard',
      diagnosis: diagnosis,
      failure: failure,
    );
    return Failure(failure);
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
    final failure = const AppFailure(
      code: RejectionCodes.blacklisted,
      message: 'Blocked number — processing skipped before parse',
    );
    await _persistPipelineDiagnostic(
      event: event,
      messageId: message.id,
      stage: 'blocked_number',
      failure: failure,
    );
    return Failure(failure);
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
