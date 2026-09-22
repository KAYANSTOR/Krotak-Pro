import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/pending_attention_alarm_service.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_app_bar_title.dart';

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
        ).timeout(const Duration(seconds: 10));
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
    try {
      final c = AppScope.of(context);
      await _loadAlertSetting();
      final result = await c.pendingReview.listPending();
      if (result is Failure<List<IncomingMessage>>) {
        throw StateError(result.error.message);
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الرسائل المعلّقة: $error';
      });
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
    final audits = await c.auditLogs.findByEntity('message', m.id).timeout(
      const Duration(seconds: 10),
    );
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
        backgroundColor: KayanColors.success,
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
                backgroundColor: KayanColors.error,
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
            icon: Icon(
              Icons.arrow_forward,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          title: const NetAppBarTitle(
            icon: Icons.pending_actions_rounded,
            title: 'الرسائل المعلّقة',
            subtitle: 'قيد التأكيد — تحتاج تدخلاً يدوياً',
          ),
          centerTitle: false,
          actions: [
            if (_alertEnabled)
              IconButton(
                tooltip: _alarm.isMuted ? 'تشغيل التنبيه' : 'كتم التنبيه',
                onPressed: _toggleMute,
                icon: Icon(
                  _alarm.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: context.kayan.primary,
                ),
              ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_alertEnabled && _rows.isNotEmpty && !_alarm.isMuted)
              Material(
                color: context.netColors.warningContainer,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notification_important,
                        color: context.netColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تنبيه نشط — عمليات تحتاج تدخلاً',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: context.netColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _toggleMute,
                        child: Text(
                          'كتم',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            color: context.netColors.warning,
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
                    color: context.netColors.warningContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: context.netColors.warning.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_top,
                        color: context.netColors.warning,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_rows.length} رسالة معلّقة بانتظار الاعتماد أو الرفض',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: context.netColors.warning,
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
                  hintStyle: TextStyle(
                    fontFamily: 'Tajawal',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
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
                              color: context.kayan.primary,
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
                  color: context.netColors.warningContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.hourglass_top,
                  size: 20,
                  color: context.netColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.sender.isEmpty ? 'محفظة غير معروفة' : m.sender,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _fmtTime(m.receivedAt),
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.netColors.warningContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _fmtAmount(row.amount),
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: context.netColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (row.phone != null && row.phone!.isNotEmpty)
            Text(
              'الجوال: ${row.phone}',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          if (row.reference != null && row.reference!.isNotEmpty)
            Text(
              'المرجع: ${row.reference}',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            row.reason,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12.5,
              color: context.netColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('اعتماد', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KayanColors.error,
                    side: const BorderSide(color: KayanColors.error),
                  ),
                  child: const Text('رفض', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
