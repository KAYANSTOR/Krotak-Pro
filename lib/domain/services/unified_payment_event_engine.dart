import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/payment_event.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'payment_fingerprint_service.dart';
import 'services.dart';

/// Single ingest path for SMS, future wallet notifications, and manual entry.
///
/// ```text
/// PaymentEvent
///   -> parse (no commercial decision)
///   -> fingerprint
///   -> persist raw IncomingMessage (deduped by fingerprint)
///   -> PD-07 auto-process gate
///   -> TransferProcessor
/// ```
final class UnifiedPaymentEventEngine implements PaymentEventEngine {
  UnifiedPaymentEventEngine({
    required this.messages,
    required this.parser,
    required this.processor,
    required this.ids,
    this.settings,
    this.fingerprints = const PaymentFingerprintService(),
  });

  final MessageRepository messages;
  final MessageParser parser;
  final TransferProcessor processor;
  final IdGenerator ids;
  final SettingsRepository? settings;
  final PaymentFingerprintService fingerprints;

  @override
  Future<Result<Transaction?>> ingest(PaymentEvent event) async {
    final provisional = event.toProvisionalMessage(id: ids.next('msg'));
    final parseResult = parser.parse(provisional);
    final parsed = parseResult is Success<ParsedTransfer>
        ? parseResult.value
        : null;
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

    final boundParse = ParsedTransfer(
      messageId: message.id,
      amount: parsed!.amount,
      customerIdentifier: parsed.customerIdentifier,
      identifierType: parsed.identifierType,
      reference: parsed.reference,
      templateId: parsed.templateId,
      rawIdentifier: parsed.rawIdentifier,
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
