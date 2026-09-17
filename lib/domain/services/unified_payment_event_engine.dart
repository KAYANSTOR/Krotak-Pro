import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'payment_fingerprint_service.dart';
import 'payment_source_guard.dart';
import 'services.dart';

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
    this.fingerprints = const PaymentFingerprintService(),
  });

  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;
  final SettingsRepository? settings;
  final PaymentSourceGuard? sourceGuard;
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

    PaymentSourceScope? sourceScope;
    if (sourceGuard != null && event.channel != PaymentChannel.manual) {
      final resolvedScope = await sourceGuard!.resolve(event);
      if (resolvedScope is Failure<PaymentSourceScope>) {
        return Failure(resolvedScope.error);
      }
      sourceScope = (resolvedScope as Success<PaymentSourceScope>).value;

      // A known POS is a strict template scope. No configured POS template
      // means the raw message is silently ignored at the trust boundary.
      if (sourceScope.templates.isEmpty) {
        if (sourceScope.isPos) return const Success(null);
        return const Failure(
          AppFailure(
            code: 'no_source_template',
            message: 'No active transfer template is linked to this payment source',
          ),
        );
      }
    }

    final provisional = event.toProvisionalMessage(id: ids.next('msg'));
    final parseResult = sourceScope != null && parser is ScopedMessageParser
        ? (parser as ScopedMessageParser).parseScoped(
            provisional,
            sourceScope.templates,
          )
        : parser.parse(provisional);

    if (parseResult is Failure<ParsedTransfer>) {
      // For a recognized POS account, a non-matching message is intentionally
      // invisible to business processing: no persistence, rejection, recovery,
      // pending review, or customer notification.
      if (sourceScope?.isPos == true &&
          parseResult.error.code == 'message_not_matched') {
        return const Success(null);
      }
    }

    final parsed = parseResult is Success<ParsedTransfer>
        ? parseResult.value
        : null;

    if (parsed != null && sourceScope != null) {
      final templateAllowed = sourceScope.templates.any(
        (template) => template.id == parsed.templateId,
      );
      if (!templateAllowed) {
        if (sourceScope.isPos) return const Success(null);
        return const Failure(
          AppFailure(
            code: 'template_source_mismatch',
            message: 'Matched template is outside the trusted source scope',
          ),
        );
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

    final boundParse = ParsedTransfer(
      messageId: message.id,
      amount: parsedTransfer.amount,
      customerIdentifier: parsedTransfer.customerIdentifier,
      identifierType: parsedTransfer.identifierType,
      reference: parsedTransfer.reference,
      templateId: parsedTransfer.templateId,
      rawIdentifier: parsedTransfer.rawIdentifier,
    );
    await messages.updateStatus(message.id, MessageProcessingStatus.parsed);

    final auto = await _autoProcessingEnabled();
    if (!auto) {
      return const Success(null);
    }

    final processResult = await processor.process(boundParse);
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
}
