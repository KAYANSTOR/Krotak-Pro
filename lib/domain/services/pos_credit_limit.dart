import '../../core/result.dart';
import '../entities/pos_account.dart';
import '../rejection_codes.dart';

/// Central POS debt-ceiling rule used by every path that increases POS debt.
abstract final class PosCreditLimit {
  /// [currentBalanceMinor] is the POS ledger balance (negative means debt).
  /// [additionalChargeMinor] is the positive amount the new order would add
  /// to debt (unit charge × quantity).
  static AppFailure? evaluate({
    required PosAccount account,
    required int currentBalanceMinor,
    required int additionalChargeMinor,
  }) {
    final limit = account.creditLimitMinorUnits;
    if (limit == null) return null;
    if (additionalChargeMinor <= 0) return null;
    final currentDebt = currentBalanceMinor < 0 ? -currentBalanceMinor : 0;
    final nextDebt = currentDebt + additionalChargeMinor;
    if (nextDebt <= limit) return null;
    final remaining = limit - currentDebt;
    return AppFailure(
      code: RejectionCodes.creditLimitExceeded,
      message:
          'تجاوز سقف الدين المسموح لنقطة البيع ${account.name} (المتبقي ${remaining < 0 ? 0 : remaining})',
    );
  }

  static int remainingHeadroomMinor({
    required PosAccount account,
    required int currentBalanceMinor,
  }) {
    final limit = account.creditLimitMinorUnits;
    if (limit == null) return 1 << 30;
    final currentDebt = currentBalanceMinor < 0 ? -currentBalanceMinor : 0;
    final left = limit - currentDebt;
    return left < 0 ? 0 : left;
  }
}
