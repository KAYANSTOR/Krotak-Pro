import '../entities/card.dart';
import '../entities/money.dart';
import '../entities/pos_account.dart';

final class PosWholesalePricing {
  const PosWholesalePricing();

  Money unitPrice({
    required CardCategory category,
    required PosPercentageMode mode,
  }) {
    if (mode == PosPercentageMode.zero) {
      return category.faceValue;
    }
    return netAfterCommission(category);
  }

  Money charge({
    required CardCategory category,
    required PosPercentageMode mode,
    int quantity = 1,
  }) {
    final qty = quantity < 1 ? 1 : quantity;
    final unit = unitPrice(category: category, mode: mode);
    return Money(
      minorUnits: unit.minorUnits * qty,
      currencyCode: unit.currencyCode,
    );
  }

  static Money netAfterCommission(CardCategory category) {
    final bps = category.commissionPercentBps;
    if (bps <= 0) return category.faceValue;
    final clamped = bps > 10000 ? 10000 : bps;
    final face = category.faceValue.minorUnits;
    final discounted = (face * (10000 - clamped)) ~/ 10000;
    return Money(
      minorUnits: discounted < 0 ? 0 : discounted,
      currencyCode: category.faceValue.currencyCode,
    );
  }
}
