/// نسخ اختياري لملف `.krt` المشفّر إلى موقع يختاره المشغّل.
///
/// لا يوجد عميل OAuth داخل التطبيق. Google Drive يظهر داخل منتقي
/// المستندات إذا كان تطبيق Drive مثبّتًا على الجهاز. الملف المنسوخ
/// هو نفسه النسخة المشفّرة؛ لا تُرفع قاعدة مكشوفة.
final class CloudBackupCopy {
  const CloudBackupCopy._();

  static const dialogTitle = 'حفظ النسخة في Google Drive أو مجلد آخر';

  static String suggestedFileName(String sourceName) {
    final base = sourceName.trim();
    if (base.isEmpty) return 'Krotak-backup.krt';
    final leaf = base.split(RegExp(r'[/\\]')).last;
    if (leaf.toLowerCase().endsWith('.krt')) return leaf;
    return '$leaf.krt';
  }

  static bool isEncryptedPackage(String sourceName) {
    return suggestedFileName(sourceName).toLowerCase().endsWith('.krt') &&
        sourceName.trim().toLowerCase().endsWith('.krt');
  }
}
