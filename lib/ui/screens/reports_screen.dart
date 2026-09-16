import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../widgets/async_views.dart';
import 'pending_messages_screen.dart';
import 'rejected_messages_screen.dart';
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
  int _needsReview = 0;

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
    final results = await Future.wait<dynamic>([
      c.sales.listCompletedBetween(dayStart, now),
      c.sales.listCompletedBetween(monthStart, now),
      c.transactions.listRecent(limit: 200),
      c.messages.listByStatus(MessageProcessingStatus.rejected),
      c.messages.listByStatus(MessageProcessingStatus.received),
      c.messages.listByStatus(MessageProcessingStatus.parsed),
      c.messages.listByStatus(MessageProcessingStatus.failed),
    ]);
    final daily = results[0];
    final monthly = results[1];
    final recent = results[2];
    final rejected = results[3];
    final received = results[4];
    final parsed = results[5];
    final failed = results[6];
    if (!mounted) return;
    if (daily is Failure ||
        monthly is Failure ||
        recent is Failure ||
        rejected is Failure ||
        received is Failure ||
        parsed is Failure ||
        failed is Failure) {
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل التقارير؛ أعد المحاولة.';
      });
      return;
    }

    final d = (daily as Success<List<Sale>>).value;
    final m = (monthly as Success<List<Sale>>).value;
    final recentTx = (recent as Success<List<Transaction>>).value;
    final rejectedMessages = (rejected as Success<List<IncomingMessage>>).value;
    final receivedMessages = (received as Success<List<IncomingMessage>>).value;
    final parsedMessages = (parsed as Success<List<IncomingMessage>>).value;
    final failedMessages = (failed as Success<List<IncomingMessage>>).value;

    setState(() {
      _loading = false;
      _dailyCount = d.length;
      _dailyMinor = d.fold(0, (a, s) => a + s.amount.minorUnits);
      _monthlyCount = m.length;
      _monthlyMinor = m.fold(0, (a, s) => a + s.amount.minorUnits);
      _completedTx = recentTx
          .where((t) => t.status == TransactionStatus.completed)
          .length;
      _rejected = rejectedMessages.length;
      _needsReview = receivedMessages.length + parsedMessages.length + failedMessages.length;
    });
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AsyncLoadingView();
    if (_error != null) return AsyncErrorView(message: _error!, onRetry: _load);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _tile(
              title: 'مبيعات اليوم',
              value: '${formatMoneyMinor(_dailyMinor)} · $_dailyCount عملية',
              onTap: () => AppRoutes.openTransactionsLog(context),
            ),
            _tile(
              title: 'مبيعات الشهر',
              value: '${formatMoneyMinor(_monthlyMinor)} · $_monthlyCount عملية',
              onTap: () => AppRoutes.openTransactionsLog(context),
            ),
            _tile(
              title: 'سجل العمليات',
              value: '$_completedTx مكتملة من آخر 200 عملية',
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
              title: 'رسائل تحتاج مراجعة',
              value: '$_needsReview (واردة/محللة/فاشلة)',
              onTap: () => _open(const PendingMessagesScreen()),
            ),
          ],
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
          style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
        ),
        subtitle: Text(value, style: const TextStyle(fontFamily: 'Tajawal')),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
