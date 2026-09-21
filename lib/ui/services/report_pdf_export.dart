import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// يحفظ PDF تحت documents/reports ثم يشارك الملف عبر ورقة النظام.
Future<File?> saveReportPdf({
  required BuildContext context,
  required Uint8List bytes,
  required String fileStem,
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'reports'));
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final safe = fileStem.replaceAll(RegExp(r'[^\w\u0600-\u06FF\-]+'), '_');
    final file = File(p.join(reportsDir.path, '${safe}_$stamp.pdf'));
    await file.writeAsBytes(bytes, flush: true);

    if (!context.mounted) return file;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'تم إنشاء تقرير PDF',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: SelectableText(
            file.path,
            style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: file.path));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('نسخ المسار', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Share.shareXFiles(
                  [XFile(file.path, mimeType: 'application/pdf')],
                  subject: 'تقرير كروتك',
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('مشاركة', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    return file;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر حفظ PDF: $e',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    }
    return null;
  }
}
