import 'dart:typed_data';

import '../../core/result.dart';

/// WP-S1 — واجهة حفظ الملفات في مجلدات عامة **ظاهرة لمدير الملفات**.
///
/// تُستعمل في: النسخ الاحتياطي (WP-4)، تصدير السجل (WP-3/D6)،
/// وحفظ صورة إشعار العملية (WP-8/D5).
///
/// العقد:
/// - النجاح يُرجع **المسار/URI الفعلي** كما كتبه النظام لا مسارًا متوقعًا.
/// - الفشل يُرجع [AppFailure] برمز مفهوم؛ الواجهة تعرضه بالعربية عبر WP-S3.
/// - لا صلاحية تخزين واسعة على Android 10+ (MediaStore)، وعلى Android 9 فأدنى
///   كتابة مباشرة مع `WRITE_EXTERNAL_STORAGE` بحد `maxSdkVersion=28`.
abstract interface class VisibleStorageService {
  /// يحفظ [bytes] في `Download/<subfolder>/<fileName>` (D1/D2).
  Future<Result<String>> saveToDownloads({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String subfolder,
  });

  /// يحفظ صورة PNG في `Pictures/<subfolder>/<fileName>` (D5).
  Future<Result<String>> saveImageToPictures({
    required Uint8List bytes,
    required String fileName,
    String subfolder,
  });
}
