import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/services/pos_wholesale_pricing.dart';

void main() {
  const pricing = PosWholesalePricing();
  const category = CardCategory(
    id: 'cat-100',
    name: '100',
    faceValue: Money(minorUnits: 10000, currencyCode: 'YER'),
    isActive: true,
    commissionPercentBps: 1000,
  );

  test('zero mode posts full face value', () {
    final charged = pricing.charge(
      category: category,
      mode: PosPercentageMode.zero,
      quantity: 3,
    );
    expect(charged.minorUnits, 30000);
  });

  test('default category mode posts net after commission', () {
    final charged = pricing.charge(
      category: category,
      mode: PosPercentageMode.defaultCategory,
      quantity: 2,
    );
    expect(charged.minorUnits, 18000);
  });

  test('zero commission leaves face value', () {
    const plain = CardCategory(
      id: 'cat-50',
      name: '50',
      faceValue: Money(minorUnits: 5000, currencyCode: 'YER'),
      isActive: true,
    );
    expect(
      pricing
          .unitPrice(category: plain, mode: PosPercentageMode.defaultCategory)
          .minorUnits,
      5000,
    );
  });
}
