import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';

void main() {
  group('Money', () {
    test('compares by minor units and currency', () {
      const first = Money(minorUnits: 2500, currencyCode: 'YER');
      const second = Money(minorUnits: 2500, currencyCode: 'YER');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('CardReservation', () {
    test('empty reservation is not reserved', () {
      const reservation = CardReservation.none();

      expect(reservation.isReserved, isFalse);
      expect(reservation.reservationId, isNull);
    });

    test('reservation exposes its identity', () {
      final reservation = CardReservation(
        reservationId: 'reservation-1',
        reservedAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 1, 0, 5),
      );

      expect(reservation.isReserved, isTrue);
      expect(reservation.reservationId, 'reservation-1');
    });
  });
}
