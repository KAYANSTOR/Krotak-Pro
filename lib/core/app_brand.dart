/// هوية التطبيق — مصدر واحد لكل النصوص والروابط الظاهرة للمستخدم.
///
/// لتغيير الاسم أو المطوّر أو الشركة أو الموقع: عدّل هذه القيم فقط.
abstract final class AppBrand {
  /// اسم التطبيق كما يظهر في الواجهة.
  static const name = 'كروتك';

  /// الاسم اللاتيني المستخدم في أسماء ملفات النسخ الاحتياطي والمجلدات.
  static const latinName = 'kartak';

  static const version = '1.0.13';
  static const buildNumber = '13';

  static const developer = 'جارالله الكبودي';
  static const company = 'شركة كيان سوفت';
  static const website = 'kayansoft.com';
  static const description =
      'نظام إدارة شبكات الكروت والرسائل: مخزون الكروت، المبيعات، حسابات '
      'العملاء، نقاط البيع، المحافظ، العروض والتقارير — يعمل محلياً على الجهاز.';
}
