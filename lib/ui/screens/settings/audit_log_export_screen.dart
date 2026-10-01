import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/result.dart';
import '../../../domain/entities/audit.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/audit_log_export.dart';
import '../../../domain/services/report_pdf_service.dart';
import '../../app_scope.dart';
import '../../services/report_pdf_export.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

/// المرحلة 46 — تصدير سجل التدقيق CSV/PDF من القيود الحقيقية فقط.
class AuditLogExportScreen extends StatefulWidget {
  const AuditLogExportScreen({super.key});

  @override
  State<AuditLogExportScreen> createState() => _AuditLogExportScreenState();
}

class _AuditLogExportScreenState extends State<AuditLogExportScreen> {
  bool _loading = true;
  String? _error;
  List<AuditLog> _logs = const [];

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
    final result = await AppScope.of(context).auditLogs.listRecent(limit: 500);
    if (!mounted) return;
    if (result is Failure<List<AuditLog>>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _logs = (result as Success<List<AuditLog>>).value;
    });
  }

  Future<void> _shareCsv() async {
    final csv = buildAuditLogCsv(_logs);
    final dir = await getApplicationDocumentsDirectory();
    final reports = Directory(p.join(dir.path, 'reports'));
    if (!await reports.exists()) await reports.create(recursive: true);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final file = File(p.join(reports.path, 'audit_log_$stamp.csv'));
    await file.writeAsString(csv, flush: true);
    if (!mounted) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'سجل تدقيق كروتك',
    );
  }

  Future<void> _sharePdf() async {
    final container = AppScope.of(context);
    final setting = await container.settings.find(SettingKeys.networkName);
    final network = setting is Success<AppSetting?>
        ? (setting.value?.value ?? 'كروتك برو')
        : 'كروتك برو';
    final pdf = await ReportPdfService.instance();
    final bytes = await pdf.buildAuditLog(
      networkName: network,
      generatedAt: container.clock.now(),
      totalLabel: 'عدد القيود المصدّرة: ${_logs.length} (الحد 500 الأحدث)',
      rows: [
        for (final log in _logs)
          PdfTableRow([
            log.occurredAt.toIso8601String(),
            log.action,
            log.entityType,
            log.entityId,
          ]),
      ],
    );
    if (!mounted) return;
    await saveReportPdf(
      context: context,
      bytes: bytes,
      fileStem: 'audit_log',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تصدير سجل التدقيق')),
      body: _loading
          ? const AsyncLoadingView(message: 'جاري قراءة سجل التدقيق')
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    NetSurfaceCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'قيود ظاهرة: ${_logs.length}',
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'يُصدَّر أحدث 500 قيد من قاعدة الجهاز. لا تُضاف قيود وهمية، ولا يُحذف السجل عند التصدير.',
                              style: TextStyle(fontFamily: 'Tajawal'),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _logs.isEmpty ? null : _shareCsv,
                              icon: const Icon(Icons.table_chart_outlined),
                              label: const Text(
                                'مشاركة CSV',
                                style: TextStyle(fontFamily: 'Tajawal'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _logs.isEmpty ? null : _sharePdf,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text(
                                'مشاركة PDF',
                                style: TextStyle(fontFamily: 'Tajawal'),
                              ),
                            ),
                            if (_logs.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: buildAuditLogCsv(_logs)),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('تم نسخ CSV')),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text(
                                  'نسخ CSV',
                                  style: TextStyle(fontFamily: 'Tajawal'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final log in _logs.take(30))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NetSurfaceCard(
                          child: ListTile(
                            title: Text(
                              log.action,
                              style: const TextStyle(fontFamily: 'Tajawal'),
                            ),
                            subtitle: Text(
                              '${log.entityType} · ${log.entityId}\n${log.occurredAt.toIso8601String()}',
                              style: const TextStyle(fontFamily: 'Tajawal'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
