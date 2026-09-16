enum WalletStatus { active, suspended, archived }

enum PointOfSaleStatus { active, suspended, archived }

/// طريقة قراءة إشعارات/رسائل الدفع من المحفظة.
enum WalletSourceMode { sms, notification }

final class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
    this.senderId,
    this.sourceMode = WalletSourceMode.sms,
    this.packageName,
  });

  final String id;
  final String name;
  final WalletStatus status;
  final DateTime createdAt;

  /// معرف المرسل الظاهر في الرسائل/الإشعارات (مثل JAIB).
  final String? senderId;

  /// SMS أو إشعارات التطبيق.
  final WalletSourceMode sourceMode;

  /// اسم حزمة أندرويد عند القراءة من الإشعارات (مثل com.ahd.jaib).
  final String? packageName;

  Wallet copyWith({
    String? id,
    String? name,
    WalletStatus? status,
    DateTime? createdAt,
    String? senderId,
    WalletSourceMode? sourceMode,
    String? packageName,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      senderId: senderId ?? this.senderId,
      sourceMode: sourceMode ?? this.sourceMode,
      packageName: packageName ?? this.packageName,
    );
  }
}

final class PointOfSale {
  const PointOfSale({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String name;
  final PointOfSaleStatus status;
  final DateTime createdAt;
}
