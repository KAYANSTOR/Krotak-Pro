import 'wallet.dart';

/// وضع نسبة عمولة نقطة البيع — 1.0.9.
enum PosPercentageMode {
  defaultCategory,
  zero,
}

/// Binding between a catalog [PointOfSale] and the customer ledger account
/// that carries POS debt. Identifiers are payment-facing keys (phone, account,
/// name) used to recognize incoming settlements.
final class PosAccount {
  const PosAccount({
    required this.posId,
    required this.customerId,
    required this.name,
    required this.identifiers,
    this.notifyPhone,
    this.status = PointOfSaleStatus.active,
    this.percentageMode = PosPercentageMode.defaultCategory,
    this.creditLimitMinorUnits,
  });

  final String posId;
  final String customerId;
  final String name;
  final List<String> identifiers;
  final String? notifyPhone;
  final PointOfSaleStatus status;
  final PosPercentageMode percentageMode;

  /// سقف الدين المسموح به لنقطة البيع (بالهللة/الوحدة الصغرى). null = بلا سقف.
  final int? creditLimitMinorUnits;

  PosAccount copyWith({
    String? customerId,
    String? name,
    List<String>? identifiers,
    String? notifyPhone,
    PointOfSaleStatus? status,
    PosPercentageMode? percentageMode,
    int? creditLimitMinorUnits,
    bool clearNotifyPhone = false,
    bool clearCreditLimit = false,
  }) {
    return PosAccount(
      posId: posId,
      customerId: customerId ?? this.customerId,
      name: name ?? this.name,
      identifiers: identifiers ?? this.identifiers,
      notifyPhone: clearNotifyPhone ? null : (notifyPhone ?? this.notifyPhone),
      status: status ?? this.status,
      percentageMode: percentageMode ?? this.percentageMode,
      creditLimitMinorUnits: clearCreditLimit
          ? null
          : (creditLimitMinorUnits ?? this.creditLimitMinorUnits),
    );
  }

  Map<String, Object?> toJson() => {
        'posId': posId,
        'customerId': customerId,
        'name': name,
        'identifiers': identifiers,
        'notifyPhone': notifyPhone,
        'status': status.name,
        'percentageMode': percentageMode.name,
        'creditLimitMinorUnits': creditLimitMinorUnits,
      };

  /// Defensive decoder for persisted settings. Old/corrupt records must never
  /// crash the UI with a null-check operator; invalid required fields are
  /// rejected explicitly and handled by the registry as corrupt data.
  static PosAccount fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value;
      throw FormatException('Invalid POS account field: $key');
    }

    final rawIds = json['identifiers'];
    final modeRaw = json['percentageMode'] as String?;
    final statusRaw = json['status'] as String?;

    final status = _parseStatus(statusRaw);
    final percentageMode = _parsePercentageMode(modeRaw);

    return PosAccount(
      posId: requiredString('posId'),
      customerId: requiredString('customerId'),
      name: requiredString('name'),
      identifiers: rawIds is List
          ? rawIds.whereType<String>().where((e) => e.trim().isNotEmpty).toList(growable: false)
          : const <String>[],
      notifyPhone: json['notifyPhone'] as String?,
      status: status,
      percentageMode: percentageMode,
      creditLimitMinorUnits: (json['creditLimitMinorUnits'] as num?)?.toInt(),
    );
  }

  static PointOfSaleStatus _parseStatus(String? raw) {
    if (raw == null) return PointOfSaleStatus.active;
    for (final value in PointOfSaleStatus.values) {
      if (value.name == raw) return value;
    }
    return PointOfSaleStatus.active;
  }

  static PosPercentageMode _parsePercentageMode(String? raw) {
    if (raw == null) return PosPercentageMode.defaultCategory;
    for (final value in PosPercentageMode.values) {
      if (value.name == raw) return value;
    }
    return PosPercentageMode.defaultCategory;
  }
}
