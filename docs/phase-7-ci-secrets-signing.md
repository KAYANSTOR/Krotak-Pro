# المرحلة 7 — توقيع CI عبر GitHub Secrets فقط

**التاريخ:** 2026-09-21  
**الفرع:** `development/full-completion`  
**الحالة:** منفّذ في workflow — يحتاج المالك لتعبئة الأسرار قبل نجاح بناء الإصدار

## ما تغيّر

- بناء APK الإصداري في `.github/workflows/ci.yml` لم يعد يسقط إلى `android/signing/net-upload.jks.b64`.
- الأسرار المطلوبة:
  - `APK_KEYSTORE_B64`
  - `APK_KEYSTORE_PASSWORD`
  - `APK_KEY_PASSWORD`
  - `APK_KEY_ALIAS`
- يُفكّ الـ JKS داخل الـ Runner فقط ويُنشأ `android/key.properties` مؤقتاً.
- بعد البناء تُحذف ملفات التوقيع المؤقتة.
- لا تُطبع قيم الأسرار في السجلات.

## ما لم يُنفَّذ عمداً

- لم يُحذف `android/signing/net-upload.jks.b64` من Git في هذه المرحلة.
- السبب: المفتاح الحالي قد يكون مستخدماً في أجهزة مثبتة؛ تدويره يمنع التحديث فوق النسخة الحالية.
- قرار الحذف/التدوير يبقى للمالك بعد مراجعة توزيع الإصدارات.

## خطوة المالك

1. Repository → Settings → Secrets and variables → Actions.
2. إضافة الأسرار الأربعة أعلاه (نفس مفتاح التوزيع الحالي إن أردت التحديث فوق التطبيقات المثبتة).
3. تشغيل workflow يدوياً والتحقق من نجاح `build-apk`.
