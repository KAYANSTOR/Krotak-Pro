import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/pending_attention_alarm_service.dart';
import '../app_scope.dart';
import '../widgets/async_views.dart';

/// الرسائل المعلّقة (قيد التأكيد) — مطابقة منطق الفيديو + Domain.
///
/// - تنبيه صوتي/مرئي + كتم
/// - بحث بالجوال
/// - بطاقة: محفظة · جوال · مبلغ · مرجع · سبب
/// - اعتماد → pendingReview.approve (إيداع ذري)
/// - رفض → pendingReview.reject (نقل للمرفوضة)
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
  bool _alertEnabled = SettingDefaults.pendingAttentionAlertEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alarm = AppScope.of(context).pendingAlarm;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _loadAlertSetting() async {
    final r = await AppScope.of(context).settings.find(
          SettingKeys.pendingAttentionAlertEnabled,
        );
    if (!mounted) return;
    final raw = r is Success<AppSetting?> ? r.value?.value : null;
    _alertEnabled = SettingBool.read(
      raw,
      defaultValue: SettingDefaults.pendingAttentionAlertEnabled,
    );
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
    await _loadAlertSetting();
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
    if (_alertEnabled && rows.isNotEmpty && !_alarm.isMuted) {
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
    String reason = 'قيد التأكيد — تحتاج مراجعة يدوية';
    if (parse is Success<ParsedTransfer>) {
      amount = parse.value.amount;
      phone = parse.value.customerIdentifier;
      reference = parse.value.reference;
    }
    final audits = await c.auditLogs.findByEntity('message', m.id);
    if (audits is Success) {
      final logs = (audits as Success).value;
      final pending =
          logs.where((a) => a.action == 'transfer_unmatched_amount_pending');
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
      return phone.contains(q) ||
          r.message.body.contains(q) ||
          r.message.sender.contains(q);
    }).toList(growable: false);
  }

  Future<void> _approve(_PendingRow row) async {
    setState(() => _busyId = row.message.id);
    final result =
        await AppScope.of(context).pendingReview.approve(row.message.id);
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
          'تم الاعتماد وتسجيل الإيداع',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        backgroundColor: Color(0xFF059669),
      ),
    );
    await _load();
  }

  Future<void> _reject(_PendingRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'رفض الرسالة؟',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'ستُنقل إلى الرسائل المرفوضة ولن يُسجَّل إيداع.',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('رفض', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = row.message.id);
    final result =
        await AppScope.of(context).pendingReview.reject(row.message.id);
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
    await _load();
  }

  void _toggleMute() {
    if (_alarm.isMuted) {
      _alarm.unmute();
      if (_alertEnabled && _rows.isNotEmpty) _alarm.start();
    } else {
      _alarm.mute();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_forward, color: Color(0xFF0F172A)),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الرسائل المعلّقة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                'قيد التأكيد — تحتاج تدخلاً يدوياً',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          actions: [
            if (_alertEnabled)
              IconButton(
                tooltip: _alarm.isMuted ? 'تشغيل التنبيه' : 'كتم التنبيه',
                onPressed: _toggleMute,
                icon: Icon(
                  _alarm.isMuted ? Icons.volume_off : Icons.volume_up,
                  color: const Color(0xFF0F766E),
                ),
              ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_alertEnabled && _rows.isNotEmpty && !_alarm.isMuted)
              Material(
                color: const Color(0xFFFEF3C7),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notification_important,
                        color: Color(0xFFB45309),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'تنبيه نشط — عمليات تحتاج تدخلاً',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _toggleMute,
                        child: const Text(
                          'كتم',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_loading && _error == null && _rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFDBA74).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top,
                        color: Color(0xFFC2410C),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_rows.length} رسالة معلّقة بانتظار الاعتماد أو الرفض',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF9A3412),
                          ),
                        ),
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
                style: const TextStyle(fontFamily: 'Tajawal'),
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'بحث برقم جوال العميل',
                  hintStyle: const TextStyle(
                    fontFamily: 'Tajawal',
                    color: Color(0xFF94A3B8),
                  ),
                  prefixIcon:
                      const Icon(Icons.search, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
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
                              color: const Color(0xFF0F766E),
                              onRefresh: _load,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final row = _filtered[i];
                                  final busy = _busyId == row.message.id;
                                  return _PendingCard(
                                    row: row,
                                    busy: busy,
                                    onApprove: () => _approve(row),
                                    onReject: () => _reject(row),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
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
    required this.onApprove,
    required this.onReject,
  });

  final _PendingRow row;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  String _fmtAmount(Money? m) {
    if (m == null) return '—';
    final major = m.minorUnits / 100.0;
    final s = m.minorUnits % 100 == 0
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
    return '$s ${m.currencyCode}';
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour;
    final min = local.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'م' : 'ص';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$min $period';
  }

  @override
  Widget build(BuildContext context) {
    final m = row.message;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hourglass_top,
                  size: 20,
                  color: Color(0xFFEA580C),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.sender.isEmpty ? 'محفظة غير معروفة' : m.sender,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      _fmtTime(m.receivedAt),
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'معلّقة',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC2410C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.phone_android, 'الجوال', row.phone ?? '—'),
          _infoRow(Icons.payments_outlined, 'المبلغ', _fmtAmount(row.amount)),
          if (row.reference != null && row.reference!.isNotEmpty)
            _infoRow(Icons.tag, 'المرجع', row.reference!),
          _infoRow(Icons.info_outline, 'السبب', row.reason),
          const SizedBox(height: 14),
          if (busy)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'رفض',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'اعتماد',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
