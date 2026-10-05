import '../../core/result.dart';
import '../entities/cloud_account.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'cloud_account_service.dart';

/// ملخص عمولة شهر واحد — مطابق لحساب لوحة الإدارة.
final class MonthCommissionSummary {
  const MonthCommissionSummary({
    required this.monthKey,
    required this.salesTotal,
    required this.commissionDue,
    required this.paid,
    required this.uploadedCount,
  });

  /// YYYY-MM
  final String monthKey;
  final double salesTotal;
  final double commissionDue;
  final double paid;
  double get remaining => commissionDue - paid;
  final int uploadedCount;
}

/// يرفع مبيعات التطبيق المكتملة إلى Firestore ويعرض العمولة حسب نسبة اللوحة.
final class CloudCommissionService {
  CloudCommissionService({
    required this.sales,
    CloudAccountService? cloud,
  }) : _cloud = cloud ?? CloudAccountService();

  final SaleRepository sales;
  final CloudAccountService _cloud;

  double activeRate(CloudAccount account, CloudGlobalConfig config) {
    final custom = account.commissionRate;
    if (custom != null && custom > 0) return custom;
    return config.defaultCommissionRate;
  }

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// يرفع مبيعات الشهر الحالي (والمبيعات الحديثة) إلى اللوحة.
  Future<Result<int>> syncCompletedSales({
    required String uid,
    required String idToken,
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final start = from ?? DateTime(now.year, now.month, 1);
    final end = to ?? now;
    final result = await sales.listCompletedBetween(start, end);
    if (result is Failure<List<Sale>>) return Failure(result.error);
    final list = (result as Success<List<Sale>>).value;
    var uploaded = 0;
    await Future.wait(list.map((sale) async {
      if (sale.status != TransactionStatus.completed) return;
      final face = sale.amount.minorUnits / 100.0;
      try {
        await _cloud.upsertNetworkSale(
          uid: uid,
          saleId: sale.id,
          idToken: idToken,
          fields: <String, dynamic>{
            'saleId': sale.id,
            'customerId': sale.customerId,
            'cardId': sale.cardId,
            // الحقول الأساسية والمرادفات القديمة معاً حتى تقرأها إصدارات
            // لوحة الإدارة المختلفة ولا تختفي المبيعات من التقرير.
            'faceValue': face,
            'amount': face,
            'amountMinor': sale.amount.minorUnits,
            'currencyCode': sale.amount.currencyCode,
            'face_value': face,
            'commission': 0,
            'commissionAmount': 0,
            'netAmount': face,
            'status': 'COMPLETED',
            'createdAt': sale.createdAt,
            'created_at': sale.createdAt,
            'source': 'krotak_app',
          },
        );
        uploaded += 1;
      } catch (_) {
        // نتابع بقية السجلات؛ الفشل الشبكي يُعاد في المزامنة التالية.
      }
    }));
    return Success(uploaded);
  }

  /// يجمع ملخص الأشهر من مبيعات محلية + مدفوعات اللوحة.
  Future<Result<List<MonthCommissionSummary>>> buildSummaries({
    required String uid,
    required String idToken,
    required CloudAccount account,
    required CloudGlobalConfig config,
    bool includeRemotePayments = true,
  }) async {
    final rate = activeRate(account, config);
    final now = DateTime.now();
    // آخر 6 أشهر محلياً
    final from = DateTime(now.year, now.month - 5, 1);
    final salesResult = await sales.listCompletedBetween(from, now);
    if (salesResult is Failure<List<Sale>>) return Failure(salesResult.error);
    final localSales = (salesResult as Success<List<Sale>>).value;

    final months = <String, MonthCommissionSummary>{};
    void ensure(String key) {
      months.putIfAbsent(
        key,
        () => MonthCommissionSummary(
          monthKey: key,
          salesTotal: 0,
          commissionDue: 0,
          paid: 0,
          uploadedCount: 0,
        ),
      );
    }

    for (final sale in localSales) {
      if (sale.status != TransactionStatus.completed) continue;
      final key = monthKey(sale.createdAt);
      ensure(key);
      final prev = months[key]!;
      final face = sale.amount.minorUnits / 100.0;
      months[key] = MonthCommissionSummary(
        monthKey: key,
        salesTotal: prev.salesTotal + face,
        commissionDue: prev.commissionDue + face * (rate / 100.0),
        paid: prev.paid,
        uploadedCount: prev.uploadedCount + 1,
      );
    }

    if (includeRemotePayments) try {
      final payments = await _cloud.fetchNetworkPayments(uid: uid, idToken: idToken);
      for (final raw in payments) {
        final month = raw['month']?.toString() ?? '';
        if (month.isEmpty) continue;
        ensure(month);
        final amount = _asDouble(raw['amount']) ?? 0;
        final prev = months[month]!;
        months[month] = MonthCommissionSummary(
          monthKey: month,
          salesTotal: prev.salesTotal,
          commissionDue: prev.commissionDue,
          paid: prev.paid + amount,
          uploadedCount: prev.uploadedCount,
        );
      }
    } catch (_) {
      // المدفوعات اختيارية عند انقطاع الشبكة — نعرض الملخص المحلي.
    }

    final sorted = months.keys.toList()..sort((a, b) => b.compareTo(a));
    return Success([for (final k in sorted) months[k]!]);
  }

  static double? _asDouble(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
}
