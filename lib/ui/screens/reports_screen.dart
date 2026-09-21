import 'package:flutter/material.dart';

import '../domain/entities/setting.dart';
import '../domain/services/report_pdf_service.dart';
import 'services/report_pdf_export.dart';

import '../../core/result.dart';
import '../../domain/services/ops_report_service.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_surface_card.dart';
import '../widgets/net/net_tab_header.dart';
import 'failed_messages_screen.dart';
import 'pending_messages_screen.dart';
import 'rejected_messages_screen.dart';
import 'reports/pos_accounts_ledger_screen.dart';
import 'reports/pos_report_screen.dart';
import 'reports/sales_period_report_screen.dart';
import 'transactions_log_screen.dart';

/// التقارير والمراقبة — مطابقة فيديو المنتج (أقسام الرسائل / التقارير).
///
/// الأرقام من [OpsReportService] فقط (لا بيانات وهمية). التحديث البصري لا
/// يغيّر أي استعلام أو ربط.
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


  Future<void> _exportOpsPdf() async {
    final snap = _snap;
    if (snap == null) return;
    final c = AppScope.of(context);
    final network = await c.settings.find(SettingKeys.networkName);
    var name = 'Krotak Pro';
    if (network is Success<AppSetting?>) {
      final setting = network.value;
      if (setting != null && setting.value.trim().isNotEmpty) {
        name = setting.value.trim();
      }
    }
    String money(int minor) => (minor / 100).toStringAsFixed(2);
    final rows = [
      PdfTableRow(['مبيعات اليوم (عدد)', snap.dailySalesCount.toString()]),
      PdfTableRow(['مبيعات اليوم (ر.ي)', money(snap.dailySalesMinor)]),
      PdfTableRow(['مبيعات الشهر (عدد)', snap.monthlySalesCount.toString()]),
      PdfTableRow(['مبيعات الشهر (ر.ي)', money(snap.monthlySalesMinor)]),
      PdfTableRow(['مرفوض', snap.rejectedCount.toString()]),
      PdfTableRow(['مسار مفتوح', snap.pipelineOpenCount.toString()]),
      PdfTableRow(['قيد الإرسال', snap.sendingCount.toString()]),
      PdfTableRow(['فشل قابل لإعادة المحاولة', snap.failedRetryCount.toString()]),
      PdfTableRow(['فشل نهائي', snap.failedMaxCount.toString()]),
      PdfTableRow(['كروت متاحة', snap.availableCards.toString()]),
      PdfTableRow(['عمليات مكتملة (حديثة)', snap.completedTxRecent.toString()]),
    ];
    final bytes = await (await ReportPdfService.instance()).buildOpsSnapshot(
      networkName: name,
      generatedAt: snap.asOf,
      metricRows: rows,
    );
    if (!mounted) return;
    await saveReportPdf(context: context, bytes: bytes, fileStem: 'ops_snapshot');
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AsyncLoadingView(skeleton: true, skeletonCount: 5);
    }
    if (_error != null) {
      return AsyncErrorView(message: _error!, onRetry: _load);
    }
    final s = _snap!;
    final net = context.netColors;

    return RefreshIndicator(
      onRefresh: _load,
      color: KayanPalette.of(context).primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: NetSpacing.listBottomInset,
        children: [
          NetTabHeader(
            title: 'التقارير والمراقبة',
            subtitle: 'سجلات العمليات وأخطاء النظام وتقرير المبيعات',
            icon: Icons.insights_rounded,
            actions: [
              NetHeaderAction(
                icon: Icons.picture_as_pdf_outlined,
                tooltip: 'تصدير PDF',
                onPressed: _snap == null ? null : _exportOpsPdf,
              ),
              IconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'تحديث',
                onPressed: _load,
              ),
            ],
          ),

          // ── ملخص سريع (KPI) ──
          Padding(
            padding: NetSpacing.pageH,
            child: Row(
              children: [
                Expanded(
                  child: _KpiTile(
                    label: 'مرفوضة',
                    value: '${s.rejectedCount}',
                    icon: Icons.error_outline_rounded,
                    color: net.rejected,
                    background: net.rejectedContainer,
                    onTap: () => _open(const RejectedMessagesScreen()),
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: _KpiTile(
                    label: 'قيد المعالجة',
                    value: '${s.pipelineOpenCount + s.sendingCount}',
                    icon: Icons.pending_actions_rounded,
                    color: net.pending,
                    background: net.pendingContainer,
                    onTap: () => _open(const PendingMessagesScreen()),
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: _KpiTile(
                    label: 'فاشلة',
                    value: '${s.failedRetryCount + s.failedMaxCount}',
                    icon: Icons.report_gmailerrorred_rounded,
                    color: net.error,
                    background: net.errorContainer,
                    onTap: () => _open(const FailedMessagesScreen()),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: NetSpacing.sm),

          // ── ملخص المبيعات ──
          NetSurfaceCard(
            margin: NetSpacing.pageH,
            padding: NetSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart_rounded, size: NetSizes.iconSm, color: net.available),
                    const SizedBox(width: NetSpacing.sm),
                    Expanded(
                      child: Text(
                        'ملخص المبيعات',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: KayanPalette.of(context).textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'مخزون ${s.availableCards}',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: KayanPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NetSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'مبيعات اليوم',
                        value: formatMoneyMinor(s.dailySalesMinor),
                        hint: '${s.dailySalesCount} كرت',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: KayanPalette.of(context).border,
                    ),
                    Expanded(
                      child: _MiniStat(
                        label: 'مبيعات الشهر',
                        value: formatMoneyMinor(s.monthlySalesMinor),
                        hint: '${s.monthlySalesCount} كرت',
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const NetSectionTitle(title: 'الرسائل', icon: Icons.chat_bubble_outline_rounded),
          _group(
            children: [
              _row(
                context: context,
                icon: Icons.mark_email_unread_rounded,
                tint: net.rejected,
                title: 'الرسائل المرفوضة',
                subtitle: '${s.rejectedCount} رسالة رفضها قواعد العمل',
                onTap: () => _open(const RejectedMessagesScreen()),
              ),
              _row(
                context: context,
                icon: Icons.pending_actions_rounded,
                tint: net.pending,
                title: 'الرسائل المعلقة (قيد المعالجة)',
                subtitle:
                    'مراقبة الرسائل التي تم تسليمها للشبكة وبانتظار تأكيد الاستلام · ${s.pipelineOpenCount + s.sendingCount}',
                onTap: () => _open(const PendingMessagesScreen()),
              ),
              _row(
                context: context,
                icon: Icons.report_gmailerrorred_rounded,
                tint: net.error,
                title: 'الرسائل الفاشلة / مستنفدة',
                subtitle: 'إعادة محاولة ${s.failedRetryCount} · مستنفد ${s.failedMaxCount}',
                onTap: () => _open(const FailedMessagesScreen()),
              ),
            ],
          ),

          const NetSectionTitle(title: 'التقارير', icon: Icons.description_outlined),
          _group(
            children: [
              _row(
                context: context,
                icon: Icons.receipt_long_rounded,
                tint: net.info,
                title: 'سجل العمليات',
                subtitle:
                    'عرض وتتبع كامل لسجلات حركات الإيداعات وصرف الكروت للعملاء · ${s.completedTxRecent}',
                onTap: () => _open(const TransactionsLogScreen()),
              ),
              _row(
                context: context,
                icon: Icons.show_chart_rounded,
                tint: net.available,
                title: 'تقرير المبيعات',
                subtitle:
                    'مبيعات الكروت اليومية · اليوم ${formatMoneyMinor(s.dailySalesMinor)} · ${s.dailySalesCount} كرت',
                onTap: () => _open(
                  const SalesPeriodReportScreen(
                    initialRange: SalesReportRange.today,
                  ),
                ),
              ),
              _row(
                context: context,
                icon: Icons.calendar_month_rounded,
                tint: const Color(0xFF7C3AED),
                title: 'تقرير المبيعات التفصيلي',
                subtitle:
                    'شهر ${formatMoneyMinor(s.monthlySalesMinor)} · ${s.monthlySalesCount} كرت',
                onTap: () => AppRoutes.openSalesPeriodReport(context),
              ),
              _row(
                context: context,
                icon: Icons.point_of_sale_rounded,
                tint: KayanPalette.of(context).textSecondary,
                title: 'حسابات نقاط البيع',
                subtitle: 'تقرير التسوية المالية والعمولات لنقاط البيع',
                onTap: () => _open(const PosAccountsLedgerScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _group({required List<Widget> children}) {
    return NetSurfaceCard(
      margin: NetSpacing.pageH,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: NetSpacing.md,
                endIndent: NetSpacing.md,
                color: KayanPalette.of(context).border,
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _row({
    required BuildContext context,
    required IconData icon,
    required Color tint,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final palette = KayanPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NetSpacing.md,
            vertical: NetSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: NetSizes.badge,
                height: NetSizes.badge,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: palette.isDark ? 0.22 : 0.12),
                  borderRadius: NetRadii.smAll,
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(width: NetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: NetSpacing.xxs),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 12,
                        height: 1.35,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: palette.textTertiary,
                size: NetSizes.iconMd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NetSectionTitle extends StatelessWidget {
  const NetSectionTitle({super.key, required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.xl,
        NetSpacing.xl,
        NetSpacing.xl,
        NetSpacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: NetSizes.iconSm, color: palette.primary),
            const SizedBox(width: NetSpacing.sm),
          ],
          Text(
            title,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: palette.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NetSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.sm,
        vertical: NetSpacing.md,
      ),
      radius: NetRadii.md,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: background,
              borderRadius: NetRadii.xsAll,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: NetSpacing.sm),
          Text(
            value,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: KayanPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.hint,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final String hint;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: NetSpacing.xxs),
        Text(
          value,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        Text(
          hint,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 11,
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }
}
