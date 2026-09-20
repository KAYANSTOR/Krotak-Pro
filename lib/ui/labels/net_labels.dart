import 'package:flutter/material.dart';

import '../../domain/entities/broadcast.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/promotion.dart';
import '../../domain/entities/transaction.dart';
import '../theme/net_semantic_colors.dart';

/// Arabic display labels for domain enums.
///
/// Presentation-only: the domain enums stay untouched, and screens stop leaking
/// raw English enum names into the Arabic UI.
String transactionTypeLabel(TransactionType type) => switch (type) {
      TransactionType.deposit => 'إيداع / تحويل',
      TransactionType.withdrawal => 'خصم يدوي مباشر',
      TransactionType.sale => 'صرف كرت',
      TransactionType.settlement => 'تسوية نقطة بيع',
      TransactionType.reversal => 'إلغاء / عكس',
      TransactionType.advance => 'سلفني (آجل)',
      TransactionType.reward => 'كرت مكافأة',
    };

IconData transactionTypeIcon(TransactionType type) => switch (type) {
      TransactionType.deposit => Icons.south_west_rounded,
      TransactionType.withdrawal => Icons.north_east_rounded,
      TransactionType.sale => Icons.style_rounded,
      TransactionType.settlement => Icons.storefront_rounded,
      TransactionType.reversal => Icons.undo_rounded,
      TransactionType.advance => Icons.hourglass_bottom_rounded,
      TransactionType.reward => Icons.card_giftcard_rounded,
    };

String transactionStatusLabel(TransactionStatus status) => switch (status) {
      TransactionStatus.pending => 'قيد التنفيذ',
      TransactionStatus.completed => 'مكتملة',
      TransactionStatus.reversed => 'ملغاة',
      TransactionStatus.rejected => 'مرفوضة',
    };

Color transactionStatusColor(TransactionStatus status, NetSemanticColors net) =>
    switch (status) {
      TransactionStatus.pending => net.pending,
      TransactionStatus.completed => net.success,
      TransactionStatus.reversed => net.warning,
      TransactionStatus.rejected => net.rejected,
    };

Color transactionStatusContainer(TransactionStatus status, NetSemanticColors net) =>
    switch (status) {
      TransactionStatus.pending => net.pendingContainer,
      TransactionStatus.completed => net.successContainer,
      TransactionStatus.reversed => net.warningContainer,
      TransactionStatus.rejected => net.rejectedContainer,
    };

String cardStatusLabel(CardStatus status) => switch (status) {
      CardStatus.available => 'متاح',
      CardStatus.reserved => 'محجوز',
      CardStatus.sold => 'مباع',
      CardStatus.disabled => 'معطّل',
      CardStatus.expired => 'منتهي',
    };

Color cardStatusColor(CardStatus status, NetSemanticColors net) => switch (status) {
      CardStatus.available => net.available,
      CardStatus.reserved => net.reserved,
      CardStatus.sold => net.sold,
      CardStatus.disabled => net.rejected,
      CardStatus.expired => net.warning,
    };

Color cardStatusContainer(CardStatus status, NetSemanticColors net) => switch (status) {
      CardStatus.available => net.availableContainer,
      CardStatus.reserved => net.reservedContainer,
      CardStatus.sold => net.soldContainer,
      CardStatus.disabled => net.rejectedContainer,
      CardStatus.expired => net.warningContainer,
    };

String customerStatusLabel(CustomerStatus status) => switch (status) {
      CustomerStatus.active => 'نشط',
      CustomerStatus.provisional => 'دفتر مؤقت',
      CustomerStatus.blacklisted => 'قائمة سوداء',
      CustomerStatus.merged => 'مدموج',
      CustomerStatus.archived => 'مؤرشف',
    };

String messageStatusLabel(MessageProcessingStatus status) => switch (status) {
      MessageProcessingStatus.received => 'مستلمة',
      MessageProcessingStatus.parsed => 'مقروءة',
      MessageProcessingStatus.pending => 'معلّقة',
      MessageProcessingStatus.sending => 'قيد الإرسال',
      MessageProcessingStatus.processed => 'معالجة',
      MessageProcessingStatus.failedMaxAttempts => 'استنفدت المحاولات',
      MessageProcessingStatus.rejected => 'مرفوضة',
      MessageProcessingStatus.recovered => 'مُستردّة',
      MessageProcessingStatus.failed => 'فاشلة',
    };

Color messageStatusColor(MessageProcessingStatus status, NetSemanticColors net) =>
    switch (status) {
      MessageProcessingStatus.received => net.info,
      MessageProcessingStatus.parsed => net.pending,
      MessageProcessingStatus.pending => net.pending,
      MessageProcessingStatus.sending => net.pending,
      MessageProcessingStatus.processed => net.success,
      MessageProcessingStatus.failedMaxAttempts => net.rejected,
      MessageProcessingStatus.rejected => net.rejected,
      MessageProcessingStatus.recovered => net.warning,
      MessageProcessingStatus.failed => net.error,
    };

Color messageStatusContainer(
  MessageProcessingStatus status,
  NetSemanticColors net,
) =>
    switch (status) {
      MessageProcessingStatus.received => net.infoContainer,
      MessageProcessingStatus.parsed => net.pendingContainer,
      MessageProcessingStatus.pending => net.pendingContainer,
      MessageProcessingStatus.sending => net.pendingContainer,
      MessageProcessingStatus.processed => net.successContainer,
      MessageProcessingStatus.failedMaxAttempts => net.rejectedContainer,
      MessageProcessingStatus.rejected => net.rejectedContainer,
      MessageProcessingStatus.recovered => net.warningContainer,
      MessageProcessingStatus.failed => net.errorContainer,
    };

String promotionStatusLabel(PromotionStatus status) => switch (status) {
      PromotionStatus.active => 'نشط',
      PromotionStatus.disabled => 'معطّل',
    };

String broadcastStatusLabel(BroadcastJobStatus status) => switch (status) {
      BroadcastJobStatus.draft => 'مسودة',
      BroadcastJobStatus.confirmed => 'مؤكد',
      BroadcastJobStatus.running => 'جارٍ الإرسال',
      BroadcastJobStatus.paused => 'متوقف مؤقتًا',
      BroadcastJobStatus.completed => 'مكتمل',
      BroadcastJobStatus.partiallyFailed => 'مكتمل جزئيًا',
      BroadcastJobStatus.failed => 'فاشل',
      BroadcastJobStatus.cancelled => 'ملغى',
    };

Color broadcastStatusColor(BroadcastJobStatus status, NetSemanticColors net) =>
    switch (status) {
      BroadcastJobStatus.completed => net.available,
      BroadcastJobStatus.partiallyFailed => net.warning,
      BroadcastJobStatus.paused => net.warning,
      BroadcastJobStatus.failed => net.rejected,
      BroadcastJobStatus.cancelled => net.rejected,
      BroadcastJobStatus.running => net.pending,
      BroadcastJobStatus.draft => net.info,
      BroadcastJobStatus.confirmed => net.info,
    };

/// Relative Arabic time label used by message and transaction lists.
String relativeArabicTime(DateTime timestamp, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = timestamp.toLocal();
  final difference = reference.difference(local);

  if (difference.inSeconds < 60) return 'الآن';
  if (difference.inMinutes < 60) return 'قبل ${difference.inMinutes} دقيقة';
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return hours == 1 ? 'قبل ساعة' : 'قبل $hours ساعة';
  }
  if (difference.inDays < 30) {
    final days = difference.inDays;
    return days == 1 ? 'أمس' : 'قبل $days يوم';
  }
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}

/// Day header label (e.g. "اليوم" / "أمس" / "الأحد، 14 سبتمبر").
String arabicDayLabel(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final target = DateTime(date.year, date.month, date.day);
  final today = DateTime(reference.year, reference.month, reference.day);
  final difference = today.difference(target).inDays;

  if (difference == 0) return 'اليوم';
  if (difference == 1) return 'أمس';
  return arabicShortDate(target);
}

const List<String> _arabicWeekdays = <String>[
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const List<String> _arabicMonths = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String arabicShortDate(DateTime date) {
  final weekday = _arabicWeekdays[(date.weekday - 1) % 7];
  final month = _arabicMonths[(date.month - 1) % 12];
  return '$weekday، ${date.day} $month';
}
