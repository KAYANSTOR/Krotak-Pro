import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// WP-8 — تحويل بطاقة الإشعار إلى صورة PNG فعلية.
///
/// المصدر هو `RepaintBoundary` مُعطى بمفتاح؛ الخدمة لا تعرف شيئًا عن الشاشة
/// ولا عن التخزين، فيمكن اختبارها وحدها.
///
/// القرار المسجّل: تُلتقط البطاقة **المرئية** داخل ورقة تفاصيل العملية (وهي
/// دائمًا ظاهرة عند الضغط على حفظ/مشاركة)، لأن الرسم خارج الشاشة عبر
/// `RenderView` غير مستقر بين إصدارات Flutter. البطاقة نفسها مستقلة وقابلة
/// لإعادة الاستخدام في أي مكان.
final class ReceiptImageService {
  const ReceiptImageService();

  /// كثافة الرسم — صورة واضحة للطباعة/المشاركة (D5).
  static const double pixelRatio = 3;

  /// اسم ملف عربي مفهوم: `إشعار-<المرجع>.png`.
  static String fileNameFor(String reference) {
    final cleaned = reference
        .trim()
        .replaceAll(RegExp(r'[^\u0600-\u06FF\w\-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safe = cleaned.isEmpty ? 'عملية' : cleaned;
    return 'إشعار-$safe.png';
  }

  /// يرسم حدود [boundaryKey] إلى PNG. يعيد null إن لم تكن جاهزة أو فشل الرسم.
  Future<Uint8List?> capture(GlobalKey boundaryKey) async {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    if (object.size.isEmpty) return null;
    try {
      final image = await object.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// ترويسة PNG — تُستعمل في الاختبارات للتحقق أن الناتج صورة لا نص.
  static const List<int> pngSignature = <int>[0x89, 0x50, 0x4E, 0x47];

  static bool isPng(Uint8List bytes) {
    if (bytes.length < pngSignature.length) return false;
    for (var i = 0; i < pngSignature.length; i++) {
      if (bytes[i] != pngSignature[i]) return false;
    }
    return true;
  }
}
