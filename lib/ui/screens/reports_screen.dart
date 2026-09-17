import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/services/ops_report_service.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';
import 'failed_messages_screen.dart';
import 'pending_messages_screen.dart';
import 'rejected_messages_screen.dart';
import 'reports/pos_report_screen.dart';
import 'reports/sales_period_report_screen.dart';
import 'transactions_log_screen.dart';

/// التقارير والمراقبة — مطابقة فيديو المنتج (أقسام الرسائل / التقارير).
///
/// الأرقام من [OpsReportService] فقط (لا بيانات وهمية).
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'التقارير والمراقبة',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'سجلات العمليات وأخطاء النظام وتقرير المبيعات',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('الرسائل'),
              _groupCard([
                _row(
                  icon: Icons.chat_bubble_outline,
                  iconBg: const Color(0xFFFDE68A),
                  iconColor: const Color(0xFFB45309),
                  title: 'الرسائل المرفوضة',
                  subtitle: '${s.rejectedCount} رسالة مرفوضة',
                  onTap: () => _open(const RejectedMessagesScreen()),
                ),
                _row(
                  icon: Icons.pending_actions_outlined,
                  iconBg: const Color(0xFFE0F2FE),
                  iconColor: const Color(0xFF0369A1),
                  title: 'الرسائل المعلقة (قيد المعالجة)',
                  subtitle:
                      'مراقبة الرسائل التي تم تسليمها للشبكة وبانتظار تأكيد الاستلام · ${s.pipelineOpenCount + s.sendingCount}',
                  onTap: () => _open(const PendingMessagesScreen()),
                ),
                _row(
                  icon: Icons.error_outline,
                  iconBg: const Color(0xFFFEE2E2),
                  iconColor: const Color(0xFFB91C1C),
                  title: 'الرسائل الفاشلة / مستنفدة',
                  subtitle:
                      'إعادة محاولة ${s.failedRetryCount} · مستنفد ${s.failedMaxCount}',
                  onTap: () => _open(const FailedMessagesScreen()),
                ),
              ]),
              const SizedBox(height: 18),
              _sectionTitle('التقارير'),
              _groupCard([
                _row(
                  icon: Icons.receipt_long_outlined,
                  iconBg: const Color(0xFFE0F2FE),
                  iconColor: const Color(0xFF0369A1),
                  title: 'سجل العمليات',
                  subtitle:
                      'عرض وتتبع كامل لسجلات حركات الإيداعات وصرف الكروت للعملاء · ${s.completedTxRecent}',
                  onTap: () => _open(const TransactionsLogScreen()),
                ),
                _row(
                  icon: Icons.show_chart,
                  iconBg: const Color(0xFFD1FAE5),
                  iconColor: const Color(0xFF047857),
                  title: 'تقرير المبيعات',
                  subtitle:
                      'مبيعات الكروت اليومية والشهرية · اليوم ${formatMoneyMinor(s.dailySalesMinor)} · ${s.dailySalesCount} كرت',
                  onTap: () => _open(
                    const SalesPeriodReportScreen(
                      initialRange: SalesReportRange.today,
                    ),
                  ),
                ),
                _row(
                  icon: Icons.point_of_sale_outlined,
                  iconBg: const Color(0xFFE5E7EB),
                  iconColor: const Color(0xFF374151),
                  title: 'حسابات نقاط البيع',
                  subtitle: 'تقرير التسوية المالية والعمولات لنقاط البيع',
                  onTap: () => _open(const PosReportScreen()),
                ),
                _row(
                  icon: Icons.calendar_month_outlined,
                  iconBg: const Color(0xFFF3E8FF),
                  iconColor: const Color(0xFF7C3AED),
                  title: 'تقرير المبيعات التفصيلي',
                  subtitle:
                      'شهر ${formatMoneyMinor(s.monthlySalesMinor)} · ${s.monthlySalesCount} كرت · مخزون ${s.availableCards}',
                  onTap: () => AppRoutes.openSalesPeriodReport(context),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Colors.teal.shade700,
        ),
      ),
    );
  }

  Widget _groupCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
