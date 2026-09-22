import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../repositories/repositories.dart';
import '../rejection_codes.dart';
import 'services.dart';

/// Known rejection categories derived from Audit actions (PD-08).
/// Labels are product Arabic text — not invented marketing copy.
abstract final class RejectionCategories {
  static const all = 'الكل';
  static const smsDeliveryFailed = 'فشل إرسال الكود للعميل';
  static const outOfStock = 'لا يوجد مخزون كروت كافٍ يغطي الرصيد المتاح';
  static const duplicateTransfer = 'عملية تحويل مكررة، تم استلام نفس الرسالة مؤخرًا';
  static const templateMismatch = 'صيغة الرسالة لا تطابق أي قالب نشط للمحفظة';
  static const rejectedFromPending = 'مرفوضة من الرسائل المعلّقة';
  static const unresolvedCustomer = 'تعذر تحديد هوية العميل';
  static const ambiguousCategory = 'أكثر من فئة تطابق المبلغ';
  static const unmatchedAmount = 'المبلغ لا يطابق أي فئة كرت نشطة';
  static const other = 'سبب آخر';

  static String fromAuditAction(String? action) {
    switch (action) {
      case RejectionCodes.voucherSendFailed:
      case 'sms_delivery_failed':
        return smsDeliveryFailed;
      case RejectionCodes.voucherUnavailable:
      case 'transfer_out_of_stock':
      case 'transfer_reservation_failed':
        return outOfStock;
      case RejectionCodes.duplicateTransaction:
        return duplicateTransfer;
      case RejectionCodes.noActiveTemplate:
      case RejectionCodes.invalidFormat:
      case RejectionCodes.parseFailure:
      case 'message_parse_failed':
      case 'transfer_parse_failed':
      case 'no_source_template':
      case 'template_source_mismatch':
        return templateMismatch;
      case RejectionCodes.unknownSender:
      case 'transfer_unresolved':
      case 'untrusted_payment_source':
        return unresolvedCustomer;
      case RejectionCodes.categoryMismatch:
      case 'transfer_unmatched_amount':
        return unmatchedAmount;
      case RejectionCodes.missingFields:
      case RejectionCodes.blacklisted:
      case RejectionCodes.licenseBlocked:
      case RejectionCodes.creditLimitExceeded:
      case RejectionCodes.other:
      case 'transfer_rejected':
        return other;
      case 'pending_message_rejected':
        return rejectedFromPending;
      case 'transfer_ambiguous_category':
      case 'transfer_ambiguous_category_pending':
        return ambiguousCategory;
      default:
        return other;
    }
  }

  static String reasonText(String? action, {String? payloadReason}) {
    if (payloadReason != null && payloadReason.trim().isNotEmpty) {
      return payloadReason.trim();
    }
    switch (action) {
      case 'sms_delivery_failed':
        return smsDeliveryFailed;
      case 'transfer_out_of_stock':
        return outOfStock;
      case 'pending_message_rejected':
        return rejectedFromPending;
      case 'transfer_unresolved':
        return unresolvedCustomer;
      case 'transfer_ambiguous_category':
      case 'transfer_ambiguous_category_pending':
        return ambiguousCategory;
      case 'transfer_unmatched_amount':
        return unmatchedAmount;
      case 'transfer_reservation_failed':
        return 'فشل حجز الكرت من المخزون';
      case 'transfer_rejected':
        return 'رُفضت الرسالة أثناء المعالجة';
      case 'no_source_template':
        return 'لا يوجد قالب نشط مرتبط بهذا المصدر — فعّل قالب نقطة البيع';
      case 'template_source_mismatch':
        return 'القالب المطابق غير مرتبط بهذا المصدر';
      case 'untrusted_payment_source':
        return 'المصدر غير مهيّأ (محفظة أو نقطة بيع غير مسجّلة)';
      default:
        return templateMismatch;
    }
  }
}

final class RejectedMessageItem {
  const RejectedMessageItem({
    required this.message,
    required this.category,
    required this.reason,
    required this.isNew,
    this.amount,
    this.phone,
    this.reference,
    this.auditAction,
  });

  final IncomingMessage message;
  final String category;
  final String reason;
  final bool isNew;
  final Money? amount;
  final String? phone;
  final String? reference;
  final String? auditAction;
}

final class RejectedMessageCatalog {
  const RejectedMessageCatalog({
    required this.messages,
    required this.auditLogs,
    required this.parser,
  });

  final MessageRepository messages;
  final AuditLogRepository auditLogs;
  final MessageParser parser;

  static const _rejectActions = {
    'sms_delivery_failed',
    'transfer_out_of_stock',
    'pending_message_rejected',
    'transfer_unresolved',
    'transfer_ambiguous_category',
    'transfer_ambiguous_category_pending',
    'transfer_unmatched_amount',
    'transfer_reservation_failed',
    'transfer_rejected',
    'message_parse_failed',
    'transfer_parse_failed',
    'transfer_unmatched_amount_pending',
  };

  Future<Result<List<RejectedMessageItem>>> listRejected({
    DateTime? viewedAfter,
  }) async {
    final result = await messages.listByStatus(MessageProcessingStatus.rejected).timeout(
      const Duration(seconds: 15),
      onTimeout: () => const Failure(
        AppFailure(
          code: 'rejected_messages_timeout',
          message: 'انتهت مهلة تحميل الرسائل المرفوضة',
        ),
      ),
    );
    if (result is Failure<List<IncomingMessage>>) return Failure(result.error);
    final list = (result as Success<List<IncomingMessage>>).value;

    final items = <RejectedMessageItem>[];
    for (final m in list) {
      items.add(await _enrich(m, viewedAfter: viewedAfter));
    }
    items.sort((a, b) => b.message.receivedAt.compareTo(a.message.receivedAt));
    return Success(items);
  }

  Future<RejectedMessageItem> _enrich(
    IncomingMessage m, {
    DateTime? viewedAfter,
  }) async {
    Money? amount;
    String? phone;
    String? reference;
    final parse = parser.parse(m);
    if (parse is Success<ParsedTransfer>) {
      amount = parse.value.amount;
      phone = parse.value.customerIdentifier;
      reference = parse.value.reference;
    }

    String? action;
    String? payloadReason;
    final audits = await auditLogs.findByEntity('message', m.id).timeout(
      const Duration(seconds: 10),
      onTimeout: () => const Failure(
        AppFailure(
          code: 'rejected_message_details_timeout',
          message: 'انتهت مهلة تحميل تفاصيل الرسالة المرفوضة',
        ),
      ),
    );
    if (audits is Success<List<AuditLog>>) {
      final logs = audits.value;
      final relevant = logs.where((l) => _rejectActions.contains(l.action)).toList()
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      if (relevant.isNotEmpty) {
        action = relevant.first.action;
        payloadReason = _payloadField(relevant.first.payloadJson, 'reason');
      } else if (logs.isNotEmpty) {
        final last = (List<AuditLog>.of(logs)
              ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)))
            .first;
        action = last.action;
        payloadReason = _payloadField(last.payloadJson, 'reason');
      }
    }

    if (action == null && parse is Failure<ParsedTransfer>) {
      action = 'message_parse_failed';
    }

    final category = RejectionCategories.fromAuditAction(action);
    final reason = RejectionCategories.reasonText(action, payloadReason: payloadReason);
    final isNew = viewedAfter == null ? true : m.receivedAt.isAfter(viewedAfter);

    return RejectedMessageItem(
      message: m,
      category: category,
      reason: reason,
      isNew: isNew,
      amount: amount,
      phone: phone ?? m.customerIdentifier,
      reference: reference,
      auditAction: action,
    );
  }

  String? _payloadField(String? json, String name) {
    if (json == null || json.isEmpty) return null;
    final match = RegExp('"$name"\\s*:\\s*"([^"]*)"').firstMatch(json);
    return match?.group(1);
  }
}
