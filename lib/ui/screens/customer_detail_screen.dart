import 'package:flutter/material.dart';

import '../../domain/entities/setting.dart';
import '../../domain/services/report_pdf_service.dart';
import '../services/report_pdf_export.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/pos_account.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/local_promotion_progress_service.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/customer_promotion_progress.dart';
import '../widgets/customer_statement_export.dart';
import '../widgets/net/net_app_bar_title.dart';

/// مركز العميل الكامل: هوية + رصيد + دفتر + تعديل رصيد + عروض.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  bool _loading = true;
  String? _error;
  Customer? _customer;
  List<CustomerIdentifier> _ids = const [];
  CustomerAccountSummary? _summary;
  List<Transaction> _ledger = const [];
  List<PromotionProgress> _promos = const [];
  PosAccount? _posLink;

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
    final found = await c.customers.findById(widget.customerId);
    if (!mounted) return;
    if (found is Failure<Customer?>) {
      setState(() {
        _loading = false;
        _error = found.error.message;
      });
      return;
    }
    final customer = (found as Success<Customer?>).value;
    if (customer == null) {
      setState(() {
        _loading = false;
        _error = 'الحساب غير موجود';
      });
      return;
    }

    final idsR = await c.customers.listIdentifiers(widget.customerId);
    final summaryR = await c.balanceService.getAccountSummary(
      customerId: widget.customerId,
      currencyCode: 'YER',
    );
    final txR = await c.transactions.findByCustomer(widget.customerId);
    final promoR = await c.promotionProgress.forCustomer(widget.customerId);
    PosAccount? posLink;
    try {
      final posR = await c.posRegistry.findByCustomerId(widget.customerId);
      if (posR is Success<PosAccount?>) posLink = posR.value;
    } catch (_) {}

    if (!mounted) return;
    final txs = txR is Success<List<Transaction>> ? txR.value : const <Transaction>[];
    final sorted = List<Transaction>.from(txs)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _loading = false;
      _customer = customer;
      _ids = idsR is Success<List<CustomerIdentifier>> ? idsR.value : const [];
      _summary =
          summaryR is Success<CustomerAccountSummary> ? summaryR.value : null;
      _ledger = sorted;
      _promos =
          promoR is Success<List<PromotionProgress>> ? promoR.value : const [];
      _posLink = posLink;
    });
  }

  String get _primaryPhone {
    for (final id in _ids) {
      if (id.isPrimary && id.type == CustomerIdentifierType.phoneNumber) {
        return id.value;
      }
    }
    for (final id in _ids) {
      if (id.type == CustomerIdentifierType.phoneNumber) return id.value;
    }
    return '—';
  }

  String _statusLabel(CustomerStatus s) => switch (s) {
        CustomerStatus.active => 'نشط',
        CustomerStatus.provisional => 'دفتر مؤقت',
        CustomerStatus.blacklisted => 'محظور',
        CustomerStatus.merged => 'مدمج',
        CustomerStatus.archived => 'مؤرشف',
      };

  String _txTypeLabel(TransactionType t) => switch (t) {
        TransactionType.deposit => 'إيداع / دفعة',
        TransactionType.withdrawal => 'خصم رصيد',
        TransactionType.sale => 'بيع',
        TransactionType.settlement => 'تسوية',
        TransactionType.reversal => 'عكس',
        TransactionType.advance => 'سلفني',
        TransactionType.reward => 'مكافأة',
      };

  String _txStatusLabel(TransactionStatus s) => switch (s) {
        TransactionStatus.completed => 'مكتمل',
        TransactionStatus.pending => 'معلّق',
        TransactionStatus.reversed => 'معكوس',
        TransactionStatus.rejected => 'مرفوض',
      };

  String _fmtMoney(int minor) {
    final major = minor / 100.0;
    return major == major.roundToDouble()
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final d =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final t =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }


  Future<void> _exportLedgerPdf() async {
    if (_customer == null) return;
    final c = AppScope.of(context);
    final network = await c.settings.find(SettingKeys.networkName);
    var name = 'Krotak Pro';
    if (network is Success<AppSetting?>) {
      final setting = network.value;
      if (setting != null && setting.value.trim().isNotEmpty) {
        name = setting.value.trim();
      }
    }
    final rows = <PdfTableRow>[
      for (final tx in _ledger)
        PdfTableRow([
          tx.createdAt.toLocal().toString().split('.').first,
          tx.type.name,
          tx.reference ?? '—',
          (tx.amount.minorUnits / 100).toStringAsFixed(2),
          tx.status.name,
        ]),
    ];
    final bal = _summary?.balance.minorUnits ?? 0;
    final bytes = await (await ReportPdfService.instance()).buildLedgerStatement(
      title: 'كشف حساب عميل',
      accountLabel: '${_customer!.displayName} · $_primaryPhone',
      networkName: name,
      generatedAt: c.clock.now(),
      balanceLabel: 'الرصيد الحالي: ${(bal / 100).toStringAsFixed(2)} ر.ي · ${_ledger.length} حركة',
      rows: rows,
    );
    if (!mounted) return;
    await saveReportPdf(context: context, bytes: bytes, fileStem: 'customer_ledger');
  }

  Future<void> _promote() async {
    final c = AppScope.of(context);
    final r = await c.customerService.promoteToActive(widget.customerId);
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    await _load();
  }

  Future<void> _adjustBalance() async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    var isCredit = true;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final inset = MediaQuery.viewInsetsOf(ctx).bottom;
              final scheme = Theme.of(ctx).colorScheme;
              return Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: NetRadii.sheetTop,
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: NetRadii.pillAll,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'تعديل رصيد الحساب',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('إضافة رصيد', style: TextStyle(fontFamily: 'Tajawal')),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('خصم رصيد', style: TextStyle(fontFamily: 'Tajawal')),
                          ),
                        ],
                        selected: {isCredit},
                        onSelectionChanged: (s) => setLocal(() => isCredit = s.first),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'المبلغ (ر.ي)',
                          border: OutlineInputBorder(borderRadius: NetRadii.mdAll),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'السبب / البيان (مطلوب)',
                          border: OutlineInputBorder(borderRadius: NetRadii.mdAll),
                        ),
                        style: const TextStyle(fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          final raw = amountCtrl.text.trim().replaceAll(',', '');
                          final major = num.tryParse(raw);
                          if (major == null || major <= 0) return;
                          if (reasonCtrl.text.trim().isEmpty) return;
                          Navigator.of(ctx).pop(true);
                        },
                        child: const Text('تأكيد', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;
    final raw = amountCtrl.text.trim().replaceAll(',', '');
    final major = num.tryParse(raw);
    if (major == null || major <= 0) return;
    final amount = Money(minorUnits: (major * 100).round(), currencyCode: 'YER');
    final reason = reasonCtrl.text.trim();
    final c = AppScope.of(context);
    final ref = isCredit
        ? 'manual-credit:${c.ids.next('adj')}'
        : 'manual-debit:${c.ids.next('adj')}';

    final r = isCredit
        ? await c.balanceService.credit(
            customerId: widget.customerId,
            amount: amount,
            reference: ref,
            reason: reason,
          )
        : await c.balanceService.debit(
            customerId: widget.customerId,
            amount: amount,
            reference: ref,
            reason: reason,
          );

    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (r as Failure).error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCredit ? 'تمت إضافة الرصيد' : 'تم خصم الرصيد',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = context.netColors;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const NetAppBarTitle(
            title: 'ملف العميل',
            icon: Icons.person_rounded,
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (_customer != null)
              IconButton(
                tooltip: 'تصدير PDF',
                onPressed: _exportLedgerPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
            if (_customer != null)
              IconButton(
                tooltip: 'تصدير كشف',
                onPressed: () {
                  final text = buildCustomerStatementText(
                    customer: _customer!,
                    identifiers: _ids,
                    balance: _summary?.balance,
                    recent: _ledger.take(50).toList(),
                    formatMoney: (m) => m == null ? '—' : '${_fmtMoney(m.minorUnits)} ر.ي',
                    formatTime: _fmtTime,
                  );
                  showCustomerStatementExportSheet(
                    context: context,
                    statementText: text,
                    preview: Text(text, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                  );
                },
                icon: const Icon(Icons.ios_share_rounded),
              ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(message: 'جاري تحميل الحساب…')
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : _customer == null
                    ? const AsyncEmptyView(message: 'الحساب غير موجود')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          children: [
                            _identityCard(scheme, net),
                            const SizedBox(height: 12),
                            _summaryGrid(scheme, net),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _adjustBalance,
                                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                                    label: const Text(
                                      'تعديل الرصيد',
                                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                                if (_customer!.status == CustomerStatus.provisional) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _promote,
                                      icon: const Icon(Icons.verified_user_outlined, size: 18),
                                      label: const Text(
                                        'تفعيل الحساب',
                                        style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 16),
                            CustomerPromotionProgressSection(
                              items: _promos,
                              onOpenAll: () => showCustomerPromotionSheet(
                                context: context,
                                items: _promos,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'سجل العمليات (${_ledger.length})',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_ledger.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'لا توجد حركات على هذا الحساب بعد',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            else
                              ..._ledger.map((tx) => _txTile(tx, scheme, net)),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _identityCard(ColorScheme scheme, NetSemanticColors net) {
    final c = _customer!;
    final alts = _ids
        .where((i) => !(i.isPrimary && i.type == CustomerIdentifierType.phoneNumber))
        .toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: NetRadii.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.person_rounded, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName.trim().isEmpty ? 'بدون اسم' : c.displayName,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      _primaryPhone,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.status == CustomerStatus.provisional
                      ? scheme.tertiaryContainer
                      : net.successContainer,
                  borderRadius: NetRadii.pillAll,
                ),
                child: Text(
                  _statusLabel(c.status),
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: c.status == CustomerStatus.provisional
                        ? scheme.onTertiaryContainer
                        : net.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'تاريخ الإنشاء: ${_fmtTime(c.createdAt)}',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (_posLink != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.storefront_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'مرتبط بنقطة بيع: ${_posLink!.name}',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (alts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'معرفات بديلة',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: alts
                  .map(
                    (i) => Chip(
                      label: Text(
                        '${i.type.name}: ${i.value}',
                        style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryGrid(ColorScheme scheme, NetSemanticColors net) {
    final s = _summary;
    if (s == null) {
      return Text(
        'تعذر تحميل ملخص الدفتر',
        style: TextStyle(fontFamily: NetTypography.family, color: scheme.error),
      );
    }
    final bal = s.balance.minorUnits;
    final balColor = bal < 0 ? net.rejected : (bal > 0 ? net.success : scheme.onSurface);

    Widget cell(String label, String value, {Color? valueColor}) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: NetRadii.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: valueColor ?? scheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: cell(
                'الرصيد الحالي',
                '${_fmtMoney(bal)} ر.ي',
                valueColor: balColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: cell(
                'الدين الحالي',
                '${_fmtMoney(s.currentDebtMinor)} ر.ي',
                valueColor: s.currentDebtMinor > 0 ? net.rejected : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: cell('إجمالي المبيعات', '${_fmtMoney(s.totalSalesMinor)} ر.ي')),
            const SizedBox(width: 8),
            Expanded(child: cell('إجمالي الدفعات', '${_fmtMoney(s.totalDepositsMinor)} ر.ي')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: cell('الخصومات/التسويات', '${_fmtMoney(s.totalWithdrawalsMinor + s.totalSettlementsMinor)} ر.ي')),
            const SizedBox(width: 8),
            Expanded(
              child: cell(
                'سلف مفتوحة',
                s.openAdvancesCount == 0
                    ? 'لا يوجد'
                    : '${s.openAdvancesCount} · ${_fmtMoney(s.openAdvancesMinor)} ر.ي',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _txTile(Transaction tx, ColorScheme scheme, NetSemanticColors net) {
    final isCredit = ledgerIsCredit(tx.type);
    final amt = _fmtMoney(tx.amount.minorUnits);
    final title = _txTypeLabel(tx.type);
    final ref = (tx.reference ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: NetRadii.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            size: 18,
            color: isCredit ? net.success : net.rejected,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: scheme.onSurface,
                  ),
                ),
                if (ref.isNotEmpty)
                  Text(
                    ref,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  '${_fmtTime(tx.createdAt)} · ${_txStatusLabel(tx.status)}',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}$amt ر.ي',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              color: isCredit ? net.success : net.rejected,
            ),
          ),
        ],
      ),
    );
  }
}

bool ledgerIsCredit(TransactionType type) {
  switch (type) {
    case TransactionType.deposit:
    case TransactionType.reward:
    case TransactionType.reversal:
      return true;
    case TransactionType.withdrawal:
    case TransactionType.sale:
    case TransactionType.settlement:
    case TransactionType.advance:
      return false;
  }
}
