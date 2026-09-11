import 'money.dart';

enum CardStatus { available, reserved, sold, disabled, expired }

final class CardCategory {
  const CardCategory({
    required this.id,
    required this.name,
    required this.faceValue,
    required this.isActive,
  });

  final String id;
  final String name;
  final Money faceValue;
  final bool isActive;
}

final class Card {
  const Card({
    required this.id,
    required this.categoryId,
    required this.serialNumber,
    required this.secretCode,
    required this.status,
    this.reservation = const CardReservation.none(),
  });

  final String id;
  final String categoryId;
  final String serialNumber;
  final String secretCode;
  final CardStatus status;
  final CardReservation reservation;
}

final class CardReservation {
  const CardReservation.none()
      : reservationId = null,
        reservedAt = null,
        expiresAt = null;

  const CardReservation({
    required this.reservationId,
    required this.reservedAt,
    required this.expiresAt,
  });

  final String? reservationId;
  final DateTime? reservedAt;
  final DateTime? expiresAt;

  bool get isReserved => reservationId != null;
}
