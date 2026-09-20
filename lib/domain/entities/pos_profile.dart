import 'customer.dart';
import 'money.dart';
import 'pos_account.dart';
import 'wallet.dart';

/// Unified read model for a point of sale.
final class PointOfSaleProfile {
  const PointOfSaleProfile({
    required this.pointOfSale,
    required this.account,
    required this.customer,
    required this.balance,
  });

  final PointOfSale pointOfSale;
  final PosAccount? account;
  final Customer? customer;
  final Money? balance;

  bool get isLinked => account != null;
  bool get isArchived => pointOfSale.status == PointOfSaleStatus.archived;

  int get debtMinorUnits {
    final value = balance?.minorUnits ?? 0;
    return value < 0 ? -value : 0;
  }

  int get prepaidMinorUnits {
    final value = balance?.minorUnits ?? 0;
    return value > 0 ? value : 0;
  }
}
