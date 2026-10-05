/// إعداد الاتصال بمشروع Firebase المشترك مع لوحة الإدارة.
///
/// القيم هنا هي **إعداد العميل العام** لمشروع Firebase (Project ID وWeb API Key)
/// وهي ليست أسراراً: كل تطبيق Firebase يحملها في واجهته. الحماية الحقيقية للبيانات
/// تأتي من قواعد أمان Firestore وليس من إخفاء هذه القيم.
///
/// طريقتان لتمرير القيم — أيّهما استخدمت:
/// 1) تعديل [fileApiKey] و[fileProjectId] أدناه مباشرة.
/// 2) تمريرها وقت البناء (تتقدم على القيم المكتوبة هنا):
///    flutter build apk --release \
///      --dart-define=KROTAK_FIREBASE_API_KEY=... \
///      --dart-define=KROTAK_FIREBASE_PROJECT_ID=...
abstract final class CloudConfig {
  // ── القيم الحقيقية للمشروع ───────────────────────────────────────────
  /// Web API Key من Firebase Console → Project settings → General → Web API Key.
  static const fileApiKey = 'AIzaSyBxh72P7O0NqgbVuvA_kcYSM_i5MrOVkFI';

  /// Project ID من Firebase Console → Project settings → General → Project ID.
  static const fileProjectId = 'kroty-434e3';

  /// اختياري: <project-id>.firebaseapp.com
  static const fileAuthDomain = 'kroty-434e3.firebaseapp.com';

  // ── قيم البناء (--dart-define) ───────────────────────────────────────
  static const _defineApiKey = String.fromEnvironment('KROTAK_FIREBASE_API_KEY');
  static const _defineProjectId =
      String.fromEnvironment('KROTAK_FIREBASE_PROJECT_ID');
  static const _defineAuthDomain =
      String.fromEnvironment('KROTAK_FIREBASE_AUTH_DOMAIN');

  static String get apiKey => _defineApiKey.isNotEmpty ? _defineApiKey : fileApiKey;

  static String get projectId =>
      _defineProjectId.isNotEmpty ? _defineProjectId : fileProjectId;

  static String get authDomain =>
      _defineAuthDomain.isNotEmpty ? _defineAuthDomain : fileAuthDomain;

  /// لا يعمل تسجيل الحساب إلا بعد تعبئة القيم أعلاه.
  static bool get isConfigured =>
      apiKey.trim().isNotEmpty && projectId.trim().isNotEmpty;

  // ── ثوابت سلوكية ────────────────────────────────────────────────────
  /// نطاق البريد التقني: رقم الهاتف يُحوَّل داخلياً إلى بريد ثابت
  /// (الرقم + كلمة المرور) لأن Firebase لا يدعم الرقم وكلمة المرور مباشرة.
  static const emailDomain = 'krotak.app';

  /// لا توجد فترة تجريبية محلية؛ الحسابات الدائمة تُدار من لوحة الإدارة.
  static const fallbackTrialDays = 0;

  /// أقصى مدة تجربة يقبلها الخادم (مطابقة لقواعد الأمان).
  static const maxTrialDays = 30;

  /// مهلة طلبات الشبكة.
  static const requestTimeout = Duration(seconds: 20);

  /// مهلة قصيرة لإقلاع التطبيق حتى لا تتعطل شاشة التحقق عند انقطاع النت.
  static const bootNetworkTimeout = Duration(seconds: 4);

  /// دورة مزامنة حالة الحساب أثناء تشغيل التطبيق.
  static const syncInterval = Duration(minutes: 5);

  /// أقل فاصل بين تحديثات الحضور (last_seen).
  static const presenceInterval = Duration(minutes: 10);
}
