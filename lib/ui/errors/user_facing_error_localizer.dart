import '../../core/result.dart';
import '../../domain/rejection_code_labels.dart';

/// WP-S3 — رسالة موجّهة للمستخدم: نص عربي + إجراء مقترح.
final class UserFacingMessage {
  const UserFacingMessage(this.text, {this.action});

  final String text;

  /// إجراء مقترح يُعرض تحت النص (مثال: «أضف قالباً نشطاً»).
  final String? action;

  @override
  String toString() => action == null ? text : '$text — $action';
}

/// WP-S3 — مصدر واحد لتحويل أي خطأ إلى نص عربي مفهوم.
///
/// القاعدة (القسم 1.3 من خطة التنفيذ): **لا يُعرض رمز برمجي ولا نص إنجليزي
/// للمستخدم**. أي رمز غير معروف يُترجم إلى رسالة عربية عامة، والإجراء المقترح
/// يوضح ما يجب فعله.
abstract final class UserFacingErrorLocalizer {
  static const String genericText = 'تعذر إكمال العملية، حاول مرة أخرى.';

  static const UserFacingMessage generic = UserFacingMessage(genericText);

  /// الرسالة العربية لأي خطأ: [AppFailure] أو رمز نصي أو [Result].
  static UserFacingMessage localize(Object? error) {
    final code = _codeOf(error);
    if (code == null || code.trim().isEmpty) return generic;
    final normalized = code.trim();
    final known = _byCode[normalized];
    if (known != null) return known;
    final rejectionAction = _rejectionActions[normalized];
    if (rejectionAction != null || RejectionCodeLabels.ar.containsKey(normalized)) {
      return UserFacingMessage(
        RejectionCodeLabels.labelAr(normalized),
        action: rejectionAction ?? 'راجع الرسالة ثم أعد المحاولة.',
      );
    }
    return generic;
  }

  /// نص عربي فقط (بلا رمز) — تُستعمل في `SnackBar` والرسائل السريعة.
  static String message(Object? error) => localize(error).text;

  static String? _codeOf(Object? error) {
    if (error == null) return null;
    if (error is AppFailure) return error.code;
    if (error is Failure<Object?>) return error.error.code;
    if (error is String) return error;
    return null;
  }

  static const Map<String, UserFacingMessage> _byCode = {
    // ── التخزين والملفات (WP-S1/WP-3/WP-4/WP-8) ──────────────────────
    'storage_failed': UserFacingMessage(
      'تعذر حفظ الملف.',
      action: 'تأكد من وجود مساحة كافية ثم أعد المحاولة.',
    ),
    'storage_unsupported': UserFacingMessage(
      'تعذر الوصول إلى تخزين الملفات على هذا الجهاز.',
      action: 'جرّب حفظ الملف عبر المشاركة.',
    ),
    'storage_permission_denied': UserFacingMessage(
      'صلاحية التخزين مرفوضة.',
      action: 'امنح التطبيق صلاحية حفظ الملفات من إعدادات النظام.',
    ),
    'storage_invalid_arguments': UserFacingMessage('بيانات الملف غير مكتملة.'),
    'unsupported_file_type': UserFacingMessage(
      'نوع الملف غير مدعوم.',
      action: 'استخدم ملفات PDF أو Excel (xlsx) أو CSV.',
    ),
    'xlsx_parse_failed': UserFacingMessage(
      'تعذر قراءة ملف Excel.',
      action: 'تأكد أن الملف غير تالف وأن أول صف يحمل عناوين الأعمدة.',
    ),
    'invalid_card_import': UserFacingMessage(
      'ملف الاستيراد غير صالح.',
      action: 'راجع الصفوف المرفوضة في تفاصيل العملية.',
    ),
    'backup_database_invalid': UserFacingMessage(
      'ملف النسخة الاحتياطية غير صالح أو تالف.',
      action: 'اختر ملف نسخة احتياطية آخر أو أنشئ نسخة جديدة.',
    ),
    'backup_not_found': UserFacingMessage('لا توجد نسخة احتياطية بهذا الاسم.'),
    // ── الحسابات والعملاء ────────────────────────────────────────────
    'customer_not_found': UserFacingMessage(
      'العميل غير موجود.',
      action: 'أضف العميل أو تأكد من رقم الجوال.',
    ),
    'customer_not_active': UserFacingMessage(
      'حساب العميل غير مفعّل.',
      action: 'فعّل حساب العميل من ملفه ثم أعد المحاولة.',
    ),
    'customer_not_sellable': UserFacingMessage(
      'لا يمكن البيع لهذا العميل.',
      action: 'راجع حالة العميل أو سقف الدين.',
    ),
    'insufficient_balance': UserFacingMessage(
      'الرصيد غير كافٍ.',
      action: 'أضف رصيداً للعميل ثم أعد المحاولة.',
    ),
    'invalid_phone': UserFacingMessage(
      'رقم الجوال غير صالح.',
      action: 'أدخل الرقم بصيغة صحيحة مثل 77xxxxxxx.',
    ),
    'invalid_phone_identifier': UserFacingMessage(
      'رقم الجوال غير صالح.',
      action: 'أدخل الرقم بصيغة صحيحة مثل 77xxxxxxx.',
    ),
    'invalid_amount': UserFacingMessage(
      'المبلغ غير صالح.',
      action: 'أدخل مبلغاً أكبر من صفر.',
    ),
    'invalid_identifier': UserFacingMessage('المعرّف غير صالح.'),
    'duplicate_identifier': UserFacingMessage(
      'المعرّف مستخدم مسبقاً.',
      action: 'استخدم معرّفاً مختلفاً.',
    ),
    'already_has_phone': UserFacingMessage('رقم الجوال مسجّل مسبقاً لهذا العميل.'),
    'account_missing': UserFacingMessage(
      'لم يكتمل تهيئة الحساب.',
      action: 'أعد فتح التطبيق أو أنشئ الحساب من شاشة الحساب.',
    ),
    'unique_constraint': UserFacingMessage(
      'توجد بيانات مكررة تمنع الحفظ.',
      action: 'راجع القيم المدخلة ثم أعد المحاولة.',
    ),

    // ── الكروت والفئات والمخزون ──────────────────────────────────────
    'card_not_found': UserFacingMessage('الكرت غير موجود.'),
    'card_unavailable': UserFacingMessage(
      'الكرت غير متوفر في المخزون.',
      action: 'استورد كروتاً جديدة لهذه الفئة.',
    ),
    'card_not_reserved': UserFacingMessage('الكرت غير محجوز لهذه العملية.'),
    'out_of_stock': UserFacingMessage(
      'لا يوجد مخزون كافٍ.',
      action: 'استورد كروتاً جديدة أو اختر فئة أخرى.',
    ),
    'category_not_found': UserFacingMessage('فئة الكروت غير موجودة.'),
    'category_inactive': UserFacingMessage(
      'فئة الكروت غير مفعّلة.',
      action: 'فعّل الفئة من إدارة الكروت والفئات.',
    ),
    'duplicate_serial': UserFacingMessage(
      'رقم الكرت مكرر.',
      action: 'راجع الملف المستورد قبل الحفظ.',
    ),
    // ── الرسائل والقوالب ─────────────────────────────────────────────
    'message_not_found': UserFacingMessage('الرسالة غير موجودة.'),
    'message_parse_failed': UserFacingMessage(
      'تعذر تحليل نص الرسالة.',
      action: 'راجع القالب المطابق ثم أعد المعالجة.',
    ),
    'message_already_processed': UserFacingMessage('تمت معالجة هذه الرسالة مسبقاً.'),
    'no_source_template': UserFacingMessage(
      'لا يوجد قالب نشط لهذه المحفظة.',
      action: 'أضف قالباً نشطاً من قوالب الرسائل.',
    ),
    'outbound_template_unregistered': UserFacingMessage(
      'القالب غير مسجّل في النظام.',
      action: 'أعد حفظ القالب من شاشة القوالب.',
    ),
    'outbound_template_settings_read_failed': UserFacingMessage(
      'تعذر قراءة إعدادات القوالب.',
      action: 'أعد فتح شاشة القوالب ثم حاول مرة أخرى.',
    ),
    'template_source_mismatch': UserFacingMessage(
      'القالب لا يطابق مصدر الرسالة.',
      action: 'راجع قالب المصدر أو محفظة الإرسال.',
    ),
    'sms_send_failed': UserFacingMessage(
      'فشل إرسال الرسالة.',
      action: 'تحقق من شريحة الاتصال ورصيد الرسائل.',
    ),
    // ── المحافظ ونقاط البيع والعروض ──────────────────────────────────
    'wallet_not_found': UserFacingMessage('المحفظة غير موجودة.'),
    'invalid_wallet_name': UserFacingMessage('اسم المحفظة غير صالح.'),
    'untrusted_payment_source': UserFacingMessage(
      'مصدر الدفع غير موثوق.',
      action: 'راجع مصادر المحافظ المفعّلة.',
    ),
    'notification_sources_invalid': UserFacingMessage(
      'إعدادات مصادر الإشعارات غير صالحة.',
      action: 'راجع إشعارات المحافظ وامنح إذن الوصول.',
    ),
    'pos_not_found': UserFacingMessage('نقطة البيع غير موجودة.'),
    'pos_profile_invalid': UserFacingMessage(
      'ملف نقطة البيع غير مكتمل.',
      action: 'أكمل بيانات نقطة البيع ثم أعد المحاولة.',
    ),
    'pos_order_cards_missing': UserFacingMessage('طلب نقطة البيع لا يحمل كروتاً.'),
    'pos_order_card_missing': UserFacingMessage('الكرت المطلوب غير موجود في المخزون.'),
    'promo_not_found': UserFacingMessage('العرض غير موجود.'),
    'invalid_reward': UserFacingMessage(
      'قيمة المكافأة غير صالحة.',
      action: 'أدخل مكافأة أكبر من صفر.',
    ),
    'invalid_title': UserFacingMessage('العنوان مطلوب.'),
    'invalid_threshold': UserFacingMessage(
      'الحد غير صالح.',
      action: 'أدخل رقماً أكبر من صفر.',
    ),
    'invalid_pos_name': UserFacingMessage('اسم نقطة البيع غير صالح.'),

    // ── العمليات المالية (حماية فقط — لا تغيير سلوك) ─────────────────
    'duplicate_reference': UserFacingMessage('مرجع العملية مستخدم مسبقاً.'),
    'invalid_operation_id': UserFacingMessage('معرّف العملية غير صالح.'),
    'sale_ledger_missing': UserFacingMessage(
      'قيد البيع غير موجود.',
      action: 'أعد فتح العملية من سجل العمليات.',
    ),
    'sale_operation_conflict': UserFacingMessage(
      'العملية قيد التنفيذ بالفعل.',
      action: 'انتظر قليلاً ثم أعد المحاولة.',
    ),
    'mixed_currency': UserFacingMessage('لا يمكن خلط عملتين في عملية واحدة.'),
    'unmatched_amount_pending': UserFacingMessage(
      'المبلغ لا يطابق أي فئة نشطة.',
      action: 'راجع الرسالة المعلّقة واعتمدها يدوياً.',
    ),
    'broadcast_not_found': UserFacingMessage('العملية غير موجودة.'),
    'broadcast_find_failed': UserFacingMessage('تعذر قراءة العملية.'),
    'delivery_state_invalid': UserFacingMessage('حالة التسليم غير صالحة.'),
    'reward_probe_delivery_unmatched': UserFacingMessage('لا يوجد تسليم مطابق للتحقق.'),
    'reward_probe_delivery_untracked': UserFacingMessage('هذه العملية غير متتبعة للتحقق.'),
    'transfer_batch_progress_invalid': UserFacingMessage('بيانات الدفعة غير صالحة.'),
    'transfer_batch_progress_card_missing': UserFacingMessage('كرت مفقود داخل الدفعة.'),
    'unknown_verification_gate': UserFacingMessage('بوابة التحقق غير معروفة.'),
    'settings_read_failed': UserFacingMessage(
      'تعذر قراءة الإعدادات.',
      action: 'أعد فتح الشاشة ثم حاول مرة أخرى.',
    ),
    'settings_write_failed': UserFacingMessage(
      'تعذر حفظ الإعداد.',
      action: 'أعد المحاولة بعد لحظات.',
    ),
    'database_not_available': UserFacingMessage(
      'قاعدة البيانات غير متاحة.',
      action: 'أعد فتح التطبيق.',
    ),
    'cloud_http_error': UserFacingMessage(
      'تعذر الاتصال بالخدمة.',
      action: 'تحقق من الإنترنت ثم أعد المحاولة.',
    ),
    'cloud_auth_failed': UserFacingMessage(
      'بيانات الدخول غير صحيحة.',
      action: 'راجع رقم الجوال وكلمة المرور.',
    ),
    'cloud_account_disabled': UserFacingMessage(
      'الحساب موقوف من الإدارة.',
      action: 'تواصل مع الإدارة عبر واتساب.',
    ),

  };

  static const Map<String, String> _rejectionActions = {
    'voucher_send_failed': 'أعد المحاولة أو أرسل الكرت يدوياً.',
    'voucher_unavailable': 'استورد كروتاً لهذه الفئة.',
    'missing_fields': 'راجع صيغة الرسالة مع العميل.',
    'category_mismatch': 'أضف فئة مطابقة للمبلغ أو راجع الفئات.',
    'blacklisted': 'راجع حالة العميل قبل إعادة المحاولة.',
    'parse_failure': 'راجع القالب النشط للمحفظة.',
    'no_active_template': 'أضف قالباً نشطاً لهذه المحفظة.',
    'unknown_sender': 'أضف المرسل كمحفظة أو نقطة بيع.',
    'duplicate_transaction': 'راجع العملية الأصلية في سجل العمليات.',
    'invalid_format': 'راجع صيغة الرسالة المعتمدة.',
    'license_blocked': 'راجع حالة الترخيص.',
    'credit_limit_exceeded': 'راجع سقف الدين أو حصّل جزءاً من الرصيد.',
  };
}

/// غلاف واحد تستعمله الواجهة بدل `error.message` أو `error.code`.
String localizedError(Object? error) => UserFacingErrorLocalizer.message(error);
