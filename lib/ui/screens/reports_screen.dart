import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/services/ops_report_service.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import 'failed_messages_screen.dart';
import 'inventory_screen.dart';
import 'pending_messages_screen.dart';
import 'rejected_messages_screen.dart';
import 'reports/pos_report_screen.dart';
import 'reports/sales_period_report_screen.dart';

/// مركز التقارير — مربوط بـ [OpsReportService] (مصادر Domain فقط).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  String? _error;
  OpsSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final ops = OpsReportService(
      messages: c.messages,
      sales: c.sales,
      transactions: c.transactions,
      cards: c.cards,
      clock: c.clock,
    );
    final result = await ops.snapshot();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is Failure<OpsSnapshot>) {
        _error = result.error.message.isEmpty
            ? 'تعذر تحميل التقارير'
            : result.error.message;
        return;
      }
      _snap = (result as Success<OpsSnapshot>).value;
    });
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AsyncLoadingView(message: 'جاري تحميل التقارير…');
    }
    if (_error != null) {
      return AsyncErrorView(message: _error!, onRetry: _load);
    }
    final s = _snap!;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: KayanColors.appBackground,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('المبيعات والمخزون'),
              _tile(
                title: 'مبيعات اليوم',
                value:
                    '${formatMoneyMinor(s.dailySalesMinor)} · ${s.dailySalesCount} كرت',
                onTap: () => _open(
                  const SalesPeriodReportScreen(
                    initialRange: SalesReportRange.today,
                  ),
                ),
              ),
              _tile(
                title: 'مبيعات الشهر',
                value:
                    '${formatMoneyMinor(s.monthlySalesMinor)} · ${s.monthlySalesCount} كرت',
                onTap: () => _open(
                  const SalesPeriodReportScreen(
                    initialRange: SalesReportRange.month,
                  ),
                ),
              ),
              _tile(
                title: 'تقرير المبيعات التفصيلي',
                value: 'يوم / شهر / فترة مختارة',
                onTap: () => AppRoutes.openSalesPeriodReport(context),
              ),
              _tile(
                title: 'الكروت المتاحة',
                value: '${s.availableCards} كرت في المخزون',
                onTap: () => _open(const InventoryScreen()),
              ),
              _tile(
                title: 'سجل العمليات',
                value: '${s.completedTxRecent} مكتملة (آخر 200)',
                onTap: () => AppRoutes.openTransactionsLog(context),
              ),
              _tile(
                title: 'حسابات نقاط البيع',
                value: 'مستحقات + عمولة + تسوية',
                onTap: () => _open(const PosReportScreen()),
              ),
              _section('خط الرسائل'),
              _tile(
                title: 'الرسائل المرفوضة',
                value: '${s.rejectedCount} رسالة',
                onTap: () => _open(const RejectedMessagesScreen()),
              ),
              _tile(
                title: 'خط الأنابيب المفتوح',
                value:
                    '${s.pipelineOpenCount} (واردة/محللة/معلّقة/إرسال/فاشلة)',
                onTap: () => _open(const PendingMessagesScreen()),
              ),
              _tile(
                title: 'قيد الإرسال',
                value: '${s.sendingCount} رسالة',
                onTap: () => _open(const PendingMessagesScreen()),
              ),
              _tile(
                title: 'فشل يحتاج إعادة محاولة',
                value: '${s.failedRetryCount} رسالة',
                onTap: () => _open(const FailedMessagesScreen()),
              ),
              _tile(
                title: 'مستنفدة المحاولات',
                value: '${s.failedMaxCount} رسالة',
                onTap: () => _open(const FailedMessagesScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w800,
          fontSize: 14,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _tile({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(value, style: const TextStyle(fontFamily: 'Tajawal')),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
