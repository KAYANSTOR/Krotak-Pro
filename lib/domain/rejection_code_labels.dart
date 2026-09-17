import 'rejection_codes.dart';

/// Arabic product labels for the 13 screenshot rejection codes (Phase 7 UI).
abstract final class RejectionCodeLabels {
  static const Map<String, String> ar = {
    RejectionCodes.voucherSendFailed: 'فشل إرسال الكرت بعد استنفاد المحاولات',
    RejectionCodes.voucherUnavailable: 'لا يوجد مخزون كروت كافٍ في الفئة المطلوبة',
    RejectionCodes.missingFields: 'بيانات أساسية مفقودة في الرسالة',
    RejectionCodes.categoryMismatch: 'المبلغ لا يطابق أي فئة كروت نشطة',
    RejectionCodes.blacklisted: 'رقم جوال العميل مدرج في القائمة السوداء',
    RejectionCodes.parseFailure: 'تعذر تحليل الرسالة',
    RejectionCodes.noActiveTemplate: 'لا يوجد قالب نشط مطابق للمحفظة',
    RejectionCodes.unknownSender: 'مرسل غير معروف / غير مهيأ',
    RejectionCodes.duplicateTransaction: 'عملية تحويل مكررة',
    RejectionCodes.invalidFormat: 'تنسيق الرسالة غير صالح',
    RejectionCodes.licenseBlocked: 'الترخيص يمنع المعالجة',
    RejectionCodes.creditLimitExceeded: 'تجاوز سقف الدين المسموح',
    RejectionCodes.other: 'سبب آخر',
  };

  static String labelAr(String? code) {
    if (code == null || code.isEmpty) return ar[RejectionCodes.other]!;
    return ar[code] ?? code;
  }
}
