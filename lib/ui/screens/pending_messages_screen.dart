import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/pending_attention_alarm_service.dart';
import '../app_scope.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';

/// الرسائل المعلّقة + تنبيه صوتي/مرئي + كتم — 1.0.9.
class PendingMessagesScreen extends StatefulWidget {
  const PendingMessagesScreen({super.key});

  @override
  State<PendingMessagesScreen> createState() => _PendingMessagesScreenState();
}

class _PendingMessagesScreenState extends State<PendingMessagesScreen>
    with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<IncomingMessage> _all = const [];
  List<_PendingRow> _rows = const [];
  String? _busyId;
  late final PendingAttentionAlarmService _alarm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alarm = AppScope.of(context).pendingAlarm;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarm.mute();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _alarm.mute();
      setState(() {});
    }
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
    if (rows.isNotEmpty && !_alarm.isMuted) {
      _alarm.unmute();
      _alarm.start();
    } else {
      _alarm.stop();
    }
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
      final pending = logs.where((a) => a.action == 'transfer_unmatched_amount_pending');
      if (pending.isNotEmpty) reason = 'المبلغ لا يطابق أي فئة كرت نشطة';
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
      return phone.contains(q) || r.message.body.contains(q) || r.message.sender.contains(q);
    }).toList(growable: false);
  }

  Future<void> _approve(_PendingRow row) async {
    setState(() => _busyId = row.message.id);
    final result = await AppScope.of(context).pendingReview.approve(row.message.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result is Failure<Transaction>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await _load();
  }

  Future<void> _reject(_PendingRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض الرسالة؟', style: TextStyle(fontFamily: 'Tajawal')),
        content: const Text(
          'ستُنقل إلى الرسائل المرفوضة.',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('رفض', style: TextStyle(fontFamily: 'Tajawal'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = row.message.id);
    final result = await AppScope.of(context).pendingReview.reject(row.message.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await _load();
  }

  void _toggleMute() {
    if (_alarm.isMuted) {
      _alarm.unmute();
      if (_rows.isNotEmpty) _alarm.start();
    } else {
      _alarm.mute();
    }
    setState(() {});
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
        actions: [
          IconButton(
            tooltip: _alarm.isMuted ? 'تشغيل التنبيه' : 'كتم التنبيه',
            onPressed: _toggleMute,
            icon: Icon(_alarm.isMuted ? Icons.volume_off : Icons.volume_up),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_rows.isNotEmpty && !_alarm.isMuted)
            Material(
              color: const Color(0xFFFEF3C7),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.notification_important, color: Color(0xFFB45309), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'تنبيه نشط — عمليات تحتاج تدخلاً (يتوقف تلقائيًا بعد 60 ثانية)',
                        style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: Color(0xFF92400E)),
                      ),
                    ),
                    TextButton(
                      onPressed: _toggleMute,
                      child: const Text('كتم', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'بحث برقم جوال العميل',
                hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'Tajawal'),
              keyboardType: TextInputType.phone,
            ),
          ),
          Expanded(
            child: _loading
                ? const AsyncLoadingView()
                : _error != null
                    ? AsyncErrorView(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? AsyncEmptyView(
                            message: _all.isEmpty
                                ? 'لا توجد رسائل معلّقة'
                                : 'لا نتائج تطابق البحث',
                            icon: Icons.mark_email_unread_outlined,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = row.message;
    return Material(
      color: cs.surface,
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
                Icon(Icons.account_balance_wallet_outlined, size: 20, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.sender, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('معلّقة', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: accent, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('الجوال: ${row.phone ?? '—'}', style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
            Text('المبلغ: ${_fmtAmount(row.amount)}', style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
            Text('السبب: ${row.reason}', style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
            const SizedBox(height: 12),
            if (busy)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text('رفض', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: const Text('اعتماد', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
