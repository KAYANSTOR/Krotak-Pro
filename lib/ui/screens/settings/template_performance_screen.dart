import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/services/template_performance_service.dart';
import '../../app_scope.dart';
import '../../widgets/net/net_app_bar_title.dart';

/// لوحة أداء القوالب الواردة — أي قالب يُطابق فعلياً وكم مرة.
class TemplatePerformanceScreen extends StatefulWidget {
  const TemplatePerformanceScreen({super.key});

  @override
  State<TemplatePerformanceScreen> createState() =>
      _TemplatePerformanceScreenState();
}

class _TemplatePerformanceScreenState extends State<TemplatePerformanceScreen> {
  bool _loading = true;
  String? _error;
  List<TemplatePerformanceRow> _rows = const [];

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
    final listed = await c.transferTemplates.listAll();
    if (!mounted) return;
    if (listed is Failure<List<TransferTemplate>>) {
      setState(() {
        _loading = false;
        _error = listed.error.message;
      });
      return;
    }
    final templates = (listed as Success<List<TransferTemplate>>).value;
    final rows = await TemplatePerformanceService(settings: c.settings)
        .snapshot(templates);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = rows;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const NetAppBarTitle(
          icon: Icons.insights_outlined,
          title: 'أداء القوالب',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: _rows.isEmpty ? 1 : _rows.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Text(
                          'عدد مرات مطابقة كل قالب وارد منذ بدء العدّ. القوالب بلا مطابقة تظهر في الأسفل.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        );
                      }
                      if (_rows.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(child: Text('لا توجد قوالب بعد')),
                        );
                      }
                      final row = _rows[index - 1];
                      return _PerformanceTile(row: row);
                    },
                  ),
                ),
    );
  }
}

class _PerformanceTile extends StatelessWidget {
  const _PerformanceTile({required this.row});

  final TemplatePerformanceRow row;

  @override
  Widget build(BuildContext context) {
    final idle = row.matchCount == 0 && !row.unmatched;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: row.unmatched
              ? Colors.orange.withValues(alpha: 0.15)
              : idle
                  ? Colors.grey.withValues(alpha: 0.15)
                  : Colors.teal.withValues(alpha: 0.15),
          child: Text(
            '${row.matchCount}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: row.unmatched
                  ? Colors.orange.shade800
                  : idle
                      ? Colors.grey
                      : Colors.teal.shade800,
            ),
          ),
        ),
        title: Text(row.name),
        subtitle: Text(
          [
            if (row.pattern.isNotEmpty) row.pattern,
            if (!row.isActive && !row.unmatched) 'متوقف',
            if (row.lastMatchedAt != null)
              'آخر مطابقة: ${row.lastMatchedAt!.toLocal()}',
            if (idle) 'خامل — لم يُطابق أي رسالة بعد',
          ].join('\n'),
        ),
        isThreeLine: true,
      ),
    );
  }
}
