import 'money.dart';

enum CustomerStatus { active, provisional, blacklisted, merged, archived }

enum CustomerIdentifierType { phoneNumber, username, externalReference }

final class CustomerIdentifier {
  const CustomerIdentifier({
    required this.id,
    required this.customerId,
    required this.type,
    required this.value,
    required this.isPrimary,
  });

  final String id;
  final String customerId;
  final CustomerIdentifierType type;
  final String value;
  final bool isPrimary;
}

final class Customer {
  const Customer({
    required this.id,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.mergedIntoId,
  });

  final String id;
  final String displayName;
  final CustomerStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When [status] is [CustomerStatus.merged], points to the surviving account.
  final String? mergedIntoId;

  Customer copyWith({
    String? displayName,
    CustomerStatus? status,
    DateTime? updatedAt,
    String? mergedIntoId,
    bool clearMergedIntoId = false,
  }) {
    return Customer(
      id: id,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mergedIntoId:
          clearMergedIntoId ? null : (mergedIntoId ?? this.mergedIntoId),
    );
  }
}

/// نتيجة اقتراح رقم جوال من قاعدة العملاء الحقيقية (للبيع المباشر وغيره).
/// لا تُنشئ عميلاً؛ للعرض والاختيار فقط.
final class CustomerPhoneSuggestion {
  const CustomerPhoneSuggestion({
    required this.customerId,
    required this.phone,
    required this.displayName,
    required this.status,
    required this.updatedAt,
  });

  final String customerId;
  final String phone;
  final String displayName;
  final CustomerStatus status;
  final DateTime updatedAt;

  bool get isSellable =>
      status == CustomerStatus.active || status == CustomerStatus.provisional;
}

/// صف قائمة الحسابات: عميل + رصيد مجمّع + هوية أساسية في استعلام محدود.
final class CustomerAccountSnapshot {
  const CustomerAccountSnapshot({
    required this.customer,
    this.balance,
    this.primaryPhone,
    this.altId,
    this.altLabel,
  });

  final Customer customer;
  final Money? balance;
  final String? primaryPhone;
  final String? altId;
  final String? altLabel;
}
