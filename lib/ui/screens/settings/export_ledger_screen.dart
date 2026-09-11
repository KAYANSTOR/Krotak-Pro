import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

class ExportLedgerScreen extends StatefulWidget {
  const ExportLedgerScreen({super.key});
  @override
  State<ExportLedgerScreen> createState() => _ExportLedgerScreenState();
}

class _ExportLedgerScreenState extends State<ExportLedgerScreen> {
  bool _loading = true;
  String? _error;
  String _exportText = '';
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final c = AppScope.of(context);
    final r = await c.transactions.listRecent(limit: 500);
    if (!mounted) return;
    if (r is Failure<List<Transaction>>) {
      setState(() { _loading = false; _error = r.error.message; });
      return;
    }
    final txs = (r as Success<List<Transaction>>).value;
    final buf = StringBuffer('id,type,status,minor,currency,customer,reference,createdAt\n');
    for (final tx in txs) {
      buf.writeln('${tx.id},${tx.type.name},${tx.status.name},${tx.amount.minorUnits},${tx.amount.currencyCode},${tx.customerId ?? ''},${tx.reference ?? ''},${tx.createdAt.toIso8601String()}');
    }
    await c.settings.save(AppSetting(key: SettingKeys.lastExportAt, value: c.clock.now().toIso8601String(), updatedAt: c.clock.now()));
    setState(() { _loading = false; _exportText = buf.toString(); _count = txs.length; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تصدير السجل'),
        actions: [
          if (_exportText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: _exportText));
                messenger.showSnackBar(const SnackBar(content: Text('تم النسخ', style: TextStyle(fontFamily: 'Tajawal'))));
              },
            ),
        ],
      ),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : _count == 0
                  ? const AsyncEmptyView(message: 'لا حركات للتصدير')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('$_count حركة — CSV محلي', style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        SelectableText(_exportText, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ],
                    ),
    );
  }
}
