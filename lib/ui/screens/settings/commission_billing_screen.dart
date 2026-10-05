import 'package:flutter/material.dart';

import '../../../application/account_session.dart';
import '../../../core/result.dart';
import '../../../domain/services/cloud_commission_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';

/// شاشة العمولات والمبيعات الشهرية — مربوطة بلوحة الإدارة.
class CommissionBillingScreen extends StatefulWidget {
  const CommissionBillingScreen({super.key});

  @override
  State<CommissionBillingScreen> createState() => _CommissionBillingScreenState();
}

class _CommissionBillingScreenState extends State<CommissionBillingScreen> {
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  List<MonthCommissionSummary> _months = const [];
  double _rate = 5;
  int _lastUploaded = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(sync: true));
  }

  Future<void> _load({bool sync = false}) async {
    final session = AccountSession.maybeInstance;
    final state = session?.state.value;
    final account = state?.account;
    final cloudSession = state?.session;
    if (session == null || account == null || cloudSession == null) {
      setState(() {
        _loading = false;
        _error = 'يلزم تسجيل الدخول لمزامنة العمولات مع الإدارة';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      if (sync) _syncing = true;
    });

    final c = AppScope.of(context);
    final service = CloudCommissionService(sales: c.sales);
    final rate = service.activeRate(account, state!.config);

    if (sync) {
      final up = await service.syncCompletedSales(
        uid: account.uid,
        idToken: cloudSession.idToken,
      );
      if (up is Success<int>) _lastUploaded = up.value;
    }

    final result = await service.buildSummaries(
      uid: account.uid,
      idToken: cloudSession.idToken,
      account: account,
      config: state.config,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _syncing = false;
      _rate = rate;
      if (result is Success<List<MonthCommissionSummary>>) {
        _months = result.value;
      } else if (result is Failure<List<MonthCommissionSummary>>) {
        _error = result.error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final kayan = context.kayan;
    final totalDue = _months.fold<double>(0, (a, m) => a + m.commissionDue);
    final totalPaid = _months.fold<double>(0, (a, m) => a + m.paid);
    final remaining = totalDue - totalPaid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kayan.appBackground,
        appBar: AppBar(
          backgroundColor: kayan.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'العمولات والمبيعات',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'مزامنة مع الإدارة',
              onPressed: _loading || _syncing ? null : () => _load(sync: true),
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _months.isEmpty
                ? AsyncEmptyView(message: _error!, icon: Icons.cloud_off_rounded)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(NetSpacing.md),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kayan.primary,
                              kayan.primary.withValues(alpha: 0.82),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'نسبة العمولة: ${_rate.toStringAsFixed(_rate == _rate.roundToDouble() ? 0 : 1)}%',
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'من لوحة الإدارة (خاصة بالشبكة أو النسبة العامة)',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                _kpi('مستحق', totalDue),
                                _kpi('مدفوع', totalPaid),
                                _kpi('متبقي', remaining),
                              ],
                            ),
                            if (_lastUploaded > 0) ...[
                              const SizedBox(height: 10),
                              Text(
                                'آخر مزامنة: رُفع $_lastUploaded سجل بيع إلى اللوحة',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'حسب الشهر',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_months.isEmpty)
                        const AsyncEmptyView(
                          message: 'لا توجد مبيعات مكتملة بعد',
                          icon: Icons.receipt_long_outlined,
                          compact: true,
                        )
                      else
                        ..._months.map((m) => _monthCard(kayan, m)),
                    ],
                  ),
      ),
    );
  }

  Widget _kpi(String label, double value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatMinorValue(value, currency: 'ر.ي'),
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthCard(KayanPalette kayan, MonthCommissionSummary m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kayan.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kayan.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            m.monthKey,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: kayan.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _row('إجمالي المبيعات', formatMinorValue(m.salesTotal, currency: 'ر.ي')),
          _row('العمولة المستحقة', formatMinorValue(m.commissionDue, currency: 'ر.ي')),
          _row('المدفوع', formatMinorValue(m.paid, currency: 'ر.ي')),
          _row(
            'المتبقي',
            formatMinorValue(m.remaining, currency: 'ر.ي'),
            emphasize: true,
          ),
          Text(
            '${m.uploadedCount} عملية محلية',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 11.5,
              color: kayan.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    final kayan = context.kayan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                color: kayan.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? kayan.primary : kayan.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
