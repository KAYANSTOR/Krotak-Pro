enum WalletStatus { active, suspended, archived }

enum PointOfSaleStatus { active, suspended, archived }

final class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String name;
  final WalletStatus status;
  final DateTime createdAt;
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
