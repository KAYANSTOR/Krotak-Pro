import '../../core/result.dart';
import '../entities/promotion.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'local_promotion_catalog.dart';

final class PromotionProgress {
  const PromotionProgress({
    required this.promotion,
    required this.accumulatedMinor,
    required this.currencyCode,
  });

  final Promotion promotion;
  final int accumulatedMinor;
  final String currencyCode;

  int get remainingMinor =>
      (promotion.thresholdMinorUnits - accumulatedMinor).clamp(0, 1 << 30);

  double get ratio {
    if (promotion.thresholdMinorUnits <= 0) return 0;
    final r = accumulatedMinor / promotion.thresholdMinorUnits;
    return r.clamp(0.0, 1.0);
  }

  bool get qualified => accumulatedMinor >= promotion.thresholdMinorUnits;
}

/// تتبع تقدم العميل نحو عروض تراكمية نشطة.
final class LocalPromotionProgressService {
  const LocalPromotionProgressService({
    required this.promotions,
    required this.transactions,
  });

  final LocalPromotionCatalog promotions;
  final TransactionRepository transactions;

  Future<Result<List<PromotionProgress>>> forCustomer(String customerId) async {
    final listed = await promotions.listAll();
    if (listed is Failure<List<Promotion>>) return Failure(listed.error);
    final active = (listed as Success<List<Promotion>>)
        .value
        .where((p) => p.isActive)
        .toList(growable: false);
    if (active.isEmpty) return const Success(<PromotionProgress>[]);

    final txs = await transactions.findByCustomer(customerId);
    if (txs is Failure<List<Transaction>>) return Failure(txs.error);
    final completed = (txs as Success<List<Transaction>>)
        .value
        .where((t) => t.status == TransactionStatus.completed)
        .toList(growable: false);

    // تراكم مبيعات مكتملة (sale) بالعملة — يُخصم عكس البيع فقط.
    final byCurrency = <String, int>{};
    for (final t in completed) {
      final code = t.amount.currencyCode;
      if (t.type == TransactionType.sale) {
        byCurrency.update(code, (v) => v + t.amount.minorUnits, ifAbsent: () => t.amount.minorUnits);
      } else if (t.type == TransactionType.reversal &&
          (t.reference ?? '').startsWith('reversal:')) {
        byCurrency.update(code, (v) => v - t.amount.minorUnits, ifAbsent: () => -t.amount.minorUnits);
      }
    }

    return Success([
      for (final p in active)
        PromotionProgress(
          promotion: p,
          accumulatedMinor: byCurrency[p.currencyCode] ?? 0,
          currencyCode: p.currencyCode,
        ),
    ]);
  }
}
