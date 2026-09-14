import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/wallet.dart';
import '../../../domain/services/local_message_parser.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';

/// محاكاة القوالب — اختبار استخراج البيانات من رسائل SMS (مطابق للفيديو).
class TemplateSimulationScreen extends StatefulWidget {
  const TemplateSimulationScreen({super.key, this.initialWalletId});

  final String? initialWalletId;

  @override
  State<TemplateSimulationScreen> createState() => _TemplateSimulationScreenState();
}

class _TemplateSimulationScreenState extends State<TemplateSimulationScreen> {
  final _bodyCtrl = TextEditingController();
  String? _walletFilter;
  List<Wallet> _wallets = const [];
  List<TransferTemplate> _templates = const [];
  String? _result;
  bool _success = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _walletFilter = widget.initialWalletId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final w = await c.wallets.listAll();
    final t = await c.transferTemplates.listAll();
    if (!mounted) return;
    setState(() {
      if (w is Success<List<Wallet>>) _wallets = w.value;
      if (t is Success<List<TransferTemplate>>) _templates = t.value;
    });
  }

  Future<void> _simulate() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الصق نص الرسالة أولًا', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    setState(() {
      _running = true;
      _result = null;
    });

    var list = _templates.where((t) => t.isActive).toList();
    if (_walletFilter != null) {
      list = list.where((t) => t.walletId == null || t.walletId == _walletFilter).toList();
    }
    final parser = LocalMessageParser(templates: list);
    final msg = IncomingMessage(
      id: 'sim',
      sender: 'SIM',
      body: body,
      receivedAt: DateTime.now().toUtc(),
      status: MessageProcessingStatus.received,
    );
    final r = parser.parse(msg);
    if (!mounted) return;
    setState(() {
      _running = false;
      if (r is Success<ParsedTransfer>) {
        final p = r.value;
        final tpl = list.where((t) => t.id == p.templateId).firstOrNull;
        _success = true;
        _result =
            'تطابق ناجح\n'
            'القالب: ${tpl?.name ?? p.templateId ?? '—'}\n'
            'المبلغ: ${p.amount.minorUnits / 100} ${p.amount.currencyCode}\n'
            'المعرّف: ${p.customerIdentifier} (${p.identifierType.name})\n'
            'المرجع: ${p.reference}';
      } else {
        _success = false;
        _result = 'فشل التطابق\n${(r as Failure).error.message}';
      }
    });
  }

  void _clear() {
    setState(() {
      _bodyCtrl.clear();
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kayan = context.kayan;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kayan.appBackground,
        appBar: AppBar(
          backgroundColor: kayan.surface,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('محاكاة القوالب', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, color: kayan.textPrimary)),
              Text('اختبار قوالب استخراج البيانات من رسائل SMS', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: kayan.textSecondary)),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Material(
              color: kayan.surface,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('نص الرسالة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, color: kayan.textPrimary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bodyCtrl,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: 'ألصق أي رسالة هنا…',
                        hintStyle: TextStyle(fontFamily: 'Tajawal', color: kayan.textTertiary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: const TextStyle(fontFamily: 'Tajawal', height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Text('المحفظة (اختياري)', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: kayan.textSecondary)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String?>(
                      value: _walletFilter,
                      decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كل المحافظ (افتراضي)', style: TextStyle(fontFamily: 'Tajawal'))),
                        ..._wallets.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name, style: const TextStyle(fontFamily: 'Tajawal')))),
                      ],
                      onChanged: (v) => setState(() => _walletFilter = v),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clear,
                            icon: const Icon(Icons.clear_all),
                            label: const Text('مسح', style: TextStyle(fontFamily: 'Tajawal')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _running ? null : _simulate,
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(_running ? '…' : 'محاكاة', style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_result == null)
              Container(
                height: 160,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kayan.surfaceVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_outlined, size: 40, color: kayan.textTertiary),
                    const SizedBox(height: 8),
                    Text('اضغط "محاكاة" لرؤية النتيجة', style: TextStyle(fontFamily: 'Tajawal', color: kayan.textSecondary)),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_success ? const Color(0xFF059669) : const Color(0xFFDC2626)).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (_success ? const Color(0xFF059669) : const Color(0xFFDC2626)).withValues(alpha: 0.35)),
                ),
                child: Text(
                  _result!,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: _success ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
