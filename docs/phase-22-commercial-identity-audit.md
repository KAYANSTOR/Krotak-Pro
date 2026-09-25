# المرحلة 22 — تدقيق الهوية التجارية وإزالة NET الظاهر للمستخدم

**التاريخ:** 2026-09-25  
**الفرع:** `development/full-completion`  
**الأساس:** الخطة §22 محور «الهوية التجارية» و§23 بوابة الإصدار

## النطاق المنفّذ

إزالة الاسم التاريخي **NET** من النصوص الظاهرة للمستخدم واستبداله بـ`AppBrand.name` (`كروتك برو`).

| الملف | التغيير |
|------|---------|
| `permissions_onboarding.dart` | كل جمل الصلاحيات تشير إلى كروتك برو |
| `battery_settings_screen.dart` | إشعار البطارية وقائمة التحقق الميداني |
| `help_center_screen.dart` | تلميح التشغيل التلقائي بعد إعادة التشغيل |
| `net_dashboard_header.dart` | الاسم الافتراضي للشبكة عند فراغ الإعداد |
| `customer_statement_export.dart` | عنوان كشف الحساب النصي |
| `net_transaction_detail_sheet.dart` | عنوان مشاركة بيانات الحركة |

أسماء ملفات التصميم (`net_tokens`, `NetSurfaceCard`…) بقيت كما هي لأنها رموز داخلية وليست نصوص مستخدم.

## خارج النطاق (يبقى لدى المالك)

- تحقق جهاز حقيقي وفق `docs/phase-8-device-verification-checklist.md`
- أسرار توقيع GitHub
- فرع `licensing`
