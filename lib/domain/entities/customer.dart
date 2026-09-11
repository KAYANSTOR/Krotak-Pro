enum CustomerStatus { active, blacklisted, merged, archived }

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
  });

  final String id;
  final String displayName;
  final CustomerStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
}
