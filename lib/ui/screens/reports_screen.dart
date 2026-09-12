import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../widgets/async_views.dart';
import 'pending_messages_screen.dart';
import 'rejected_messages_screen.dart';
import 'reports/messages_by_status_screen.dart';
import 'reports/pos_report_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  String? _error;
  int _dailyMinor = 0;
  int _dailyCount = 0;
  int _monthlyMinor = 0;
  int _monthlyCount = 0;
  int _completedTx = 0;
  int _rejected = 0;
  int _suspended = 0;

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
    final now = c.clock.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final daily = await c.sales.listCompletedBetween(dayStart, now);
    final monthly = await c.sales.listCompletedBetween(monthStart, now);
    final recent = await c.transactions.listRecent(limit: 200);
    final rejected = await c.messages.listByStatus(MessageProcessingStatus.rejected);
    final received = await c.messages.listByStatus(MessageProcessingStatus.received);
    final parsed = await c.messages.listByStatus(MessageProcessingStatus.parsed);
    final failed = await c.messages.listByStatus(MessageProcessingStatus.failed);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (daily is Failure ||
          monthly is Failure ||
          recent is Failure ||
          rejected is Failure ||
          received is Failure ||
          parsed is Failure ||
          failed is Failure) {
        _error = 'تعذر تحميل التقارير';
        return;
      }
      final d = (daily as Success<List<Sale>>).value;
      final m = (monthly as Success<List<Sale>>).value;
      _dailyCount = d.length;
      _dailyMinor = d.fold(0, (a, s) => a + s.amount.minorUnits);
      _monthlyCount = m.length;
      _monthlyMinor = m.fold(0, (a, s) => a + s.amount.minorUnits);
      _completedTx = (recent as Success<List<Transaction>>)
          .value
          .where((t) => t.status == TransactionStatus.completed)
          .length;
      _rejected = (rejected as Success).value.length;
      _suspended = (received as Success).value.length +
          (parsed as Success).value.length +
          (failed as Success).value.length;
    });
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AsyncLoadingView();
    if (_error != null) {
      return AsyncErrorView(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tile(
            title: 'مبيعات اليوم',
            value: '${formatMoneyMinor(_dailyMinor)} · $_dailyCount',
            onTap: () => AppRoutes.openTransactionsLog(context),
          ),
          _tile(
            title: 'مبيعات الشهر',
            value: '${formatMoneyMinor(_monthlyMinor)} · $_monthlyCount',
            onTap: () => AppRoutes.openTransactionsLog(context),
          ),
          _tile(
            title: 'سجل العمليات',
            value: '$_completedTx مكتملة (آخر 200)',
            onTap: () => AppRoutes.openTransactionsLog(context),
          ),
          _tile(
            title: 'تقرير نقاط البيع',
            value: 'قائمة نقاط البيع المسجّلة',
            onTap: () => _open(const PosReportScreen()),
          ),
          _tile(
            title: 'الرسائل المرفوضة',
            value: '$_rejected رسالة',
            onTap: () => _open(const RejectedMessagesScreen()),
          ),
          _tile(
            title: 'الرسائل المعلّقة',
            value: '$_suspended (واردة/محللة/فاشلة)',
            onTap: () => _open(const PendingMessagesScreen()),
          ),
        ],
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
        title: Text(title, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        subtitle: Text(value, style: const TextStyle(fontFamily: 'Tajawal')),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
