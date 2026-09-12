import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// الرسائل المعلّقة (قيد التأكيد) — PD-07 Q4 / خطة الدفعة B2.
///
/// تعرض رسائل [MessageProcessingStatus.parsed] للمراجعة:
/// اعتماد (إيداع لحساب العميل بلا إرسال كرت) أو رفض (أرشفة كمرفوضة).
class PendingMessagesScreen extends StatefulWidget {
  const PendingMessagesScreen({super.key});

  @override
  State<PendingMessagesScreen> createState() => _PendingMessagesScreenState();
}

class _PendingMessagesScreenState extends State<PendingMessagesScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<IncomingMessage> _all = const [];
  List<_PendingRow> _rows = const [];
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.pendingReview.listPending();
    if (!mounted) return;
    if (result is Failure<List<IncomingMessage>>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
      });
      return;
    }
    final list = (result as Success<List<IncomingMessage>>).value;
    final rows = <_PendingRow>[];
    for (final m in list) {
      rows.add(await _enrich(m));
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _all = list;
      _rows = rows;
    });
  }

  Future<_PendingRow> _enrich(IncomingMessage m) async {
    final c = AppScope.of(context);
    final parse = c.messageParser.parse(m);
    Money? amount;
    String? phone;
    String? reference;
    String reason = 'قيد التأكيد';
    if (parse is Success<ParsedTransfer>) {
      amount = parse.value.amount;
      phone = parse.value.customerIdentifier;
      reference = parse.value.reference;
    }
    final audits = await c.auditLogs.findByEntity('message', m.id);
    if (audits is Success) {
      final logs = (audits as Success).value;
      final pending = logs.where(
        (a) => a.action == 'transfer_unmatched_amount_pending',
      );
      if (pending.isNotEmpty) {
        reason = 'المبلغ لا يطابق أي فئة كرت نشطة';
      }
    }
    return _PendingRow(
      message: m,
      amount: amount,
      phone: phone ?? m.customerIdentifier,
      reference: reference,
      reason: reason,
    );
  }

  List<_PendingRow> get _filtered {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final phone = r.phone ?? '';
      final body = r.message.body;
      final sender = r.message.sender;
      return phone.contains(q) || body.contains(q) || sender.contains(q);
    }).toList(growable: false);
  }

  Future<void> _approve(_PendingRow row) async {
    setState(() => _busyId = row.message.id);
    final c = AppScope.of(context);
    final result = await c.pendingReview.approve(row.message.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result is Failure<Transaction>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم اعتماد المبلغ وإضافته لحساب العميل',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
    await _load();
  }

  Future<void> _reject(_PendingRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'رفض الرسالة؟',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        content: const Text(
          'ستُنقل إلى الرسائل المرفوضة ولن تبقى في المعلّقة.',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رفض', style: TextStyle(fontFamily: 'Tajawal')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = row.message.id);
    final c = AppScope.of(context);
    final result = await c.pendingReview.reject(row.message.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم رفض الرسالة ونقلها للأرشيف',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<NetSemanticColors>();
    final pendingColor = semantic?.pending ?? cs.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الرسائل المعلّقة (قيد التأكيد)',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'مراجعة العمليات التي لم تكتمل وتحتاج إلى تأكيد',
              style: TextStyle(
                fontFamily: 'Tajawal',
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'بحث برقم جوال العميل',
                hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'Tajawal'),
              keyboardType: TextInputType.phone,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const AsyncLoadingView()
                : _error != null
                    ? AsyncErrorView(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? AsyncEmptyView(
                            message: _all.isEmpty
                                ? 'لا توجد رسائل معلّقة\nالعمليات المعلّقة أو غير المكتملة ستظهر هنا للمراجعة والتأكيد'
                                : 'لا نتائج تطابق البحث',
                            icon: Icons.mark_email_unread_outlined,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final row = _filtered[i];
                                final busy = _busyId == row.message.id;
                                return _PendingCard(
                                  row: row,
                                  busy: busy,
                                  accent: pendingColor,
                                  onApprove: () => _approve(row),
                                  onReject: () => _reject(row),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

final class _PendingRow {
  const _PendingRow({
    required this.message,
    required this.reason,
    this.amount,
    this.phone,
    this.reference,
  });

  final IncomingMessage message;
  final Money? amount;
  final String? phone;
  final String? reference;
  final String reason;
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.row,
    required this.busy,
    required this.accent,
    required this.onApprove,
    required this.onReject,
  });

  final _PendingRow row;
  final bool busy;
  final Color accent;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  String _fmtAmount(Money? m) {
    if (m == null) return '—';
    final major = m.minorUnits / 100.0;
    return '${major.toStringAsFixed(m.minorUnits % 100 == 0 ? 0 : 2)} ${m.currencyCode}';
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final d =
        '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    final h =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$d $h';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = row.message;

    return Material(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 20, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.sender,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'معلّقة',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line(Icons.phone_android, 'الجوال', row.phone ?? '—'),
            _line(Icons.payments_outlined, 'المبلغ', _fmtAmount(row.amount)),
            if (row.reference != null && row.reference!.isNotEmpty)
              _line(Icons.tag, 'المرجع', row.reference!),
            _line(Icons.schedule, 'الوقت', _fmtTime(m.receivedAt)),
            _line(Icons.info_outline, 'السبب', row.reason),
            const SizedBox(height: 12),
            if (busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text(
                        'رفض',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: const Text(
                        'اعتماد',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
