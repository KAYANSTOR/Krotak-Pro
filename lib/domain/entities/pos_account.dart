import 'wallet.dart';

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
  });

  final String posId;
  final String customerId;
  final String name;
  final List<String> identifiers;
  final String? notifyPhone;
  final PointOfSaleStatus status;

  PosAccount copyWith({
    String? customerId,
    String? name,
    List<String>? identifiers,
    String? notifyPhone,
    PointOfSaleStatus? status,
    bool clearNotifyPhone = false,
  }) {
    return PosAccount(
      posId: posId,
      customerId: customerId ?? this.customerId,
      name: name ?? this.name,
      identifiers: identifiers ?? this.identifiers,
      notifyPhone: clearNotifyPhone ? null : (notifyPhone ?? this.notifyPhone),
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
        'posId': posId,
        'customerId': customerId,
        'name': name,
        'identifiers': identifiers,
        'notifyPhone': notifyPhone,
        'status': status.name,
      };

  static PosAccount fromJson(Map<String, Object?> json) {
    final rawIds = json['identifiers'];
    return PosAccount(
      posId: json['posId']! as String,
      customerId: json['customerId']! as String,
      name: json['name']! as String,
      identifiers: rawIds is List ? rawIds.map((e) => e.toString()).toList(growable: false) : const <String>[],
      notifyPhone: json['notifyPhone'] as String?,
      status: PointOfSaleStatus.values.byName((json['status'] as String?) ?? PointOfSaleStatus.active.name),
    );
  }
}
