import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

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
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final r = await c.transactions.listRecent(limit: 500);
    if (!mounted) return;
    if (r is Failure<List<Transaction>>) {
      setState(() {
        _loading = false;
        _error = r.error.message;
      });
      return;
    }
    final txs = (r as Success<List<Transaction>>).value;
    final buf = StringBuffer('id,type,status,minor,currency,customer,reference,createdAt\n');
    for (final tx in txs) {
      buf.writeln(
        '${tx.id},${tx.type.name},${tx.status.name},${tx.amount.minorUnits},${tx.amount.currencyCode},${tx.customerId ?? ''},${tx.reference ?? ''},${tx.createdAt.toIso8601String()}',
      );
    }
    await c.settings.save(
      AppSetting(key: SettingKeys.lastExportAt, value: c.clock.now().toIso8601String(), updatedAt: c.clock.now()),
    );
    setState(() {
      _loading = false;
      _exportText = buf.toString();
      _count = txs.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تصدير السجل'),
        actions: [
          if (_exportText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: _exportText));
                messenger.showSnackBar(
                  const SnackBar(content: Text('تم النسخ')),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const AsyncLoadingView(skeleton: true, skeletonCount: 3)
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : _count == 0
                  ? AsyncEmptyView(
                      message: 'لا حركات للتصدير',
                      hint: 'سيظهر هنا ملف CSV محلي بكل الحركات المسجّلة.',
                      icon: Icons.file_download_outlined,
                      actionLabel: 'إعادة التحميل',
                      onAction: _load,
                    )
                  : ListView(
                      padding: NetSpacing.screen,
                      children: [
                        NetSurfaceCard(
                          child: Row(
                            children: [
                              Icon(
                                Icons.table_chart_outlined,
                                size: 18,
                                color: KayanPalette.of(context).primary,
                              ),
                              const SizedBox(width: NetSpacing.sm),
                              Expanded(
                                child: Text(
                                  '$_count حركة — CSV محلي (offline)',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: KayanPalette.of(context).textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: NetSpacing.md),
                        NetSurfaceCard(
                          margin: EdgeInsets.zero,
                          child: SelectableText(
                            _exportText,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
