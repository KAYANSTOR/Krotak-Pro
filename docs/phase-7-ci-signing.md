# المرحلة 7 — أمان الإصدار وتوقيع CI

**التاريخ:** 2026-09-21  
**الحالة:** منفّذة في المستودع — تنتظر تعبئة Secrets عند المالك

## ما تغيّر

- وظيفة `build-apk` تفشل إن غاب أي سر من أسرار التوقيع.
- لا سقوط إلى `android/signing/net-upload.jks.b64`.
- كلمات المرور والاسم المستعار تُقرأ من Secrets وليست مكتوبة في الـworkflow.
- الملفات المؤقتة (`key.properties` و`upload.jks`) تُحذف بعد البناء.
- اسم الأداة أصبح `krotak-pro-release-apk`.

## Secrets المطلوبة

Repository → Settings → Secrets and variables → Actions:

| السر | المعنى |
|------|--------|
| `APK_KEYSTORE_B64` | محتوى JKS/PKCS12 بعد `base64 -w 0` |
| `APK_KEYSTORE_PASSWORD` | كلمة مرور المخزن |
| `APK_KEY_PASSWORD` | كلمة مرور المفتاح |
| `APK_KEY_ALIAS` | الاسم المستعار |

توليد Base64 محلياً:

```bash
base64 -w 0 path/to/krotak-release.jks > krotak-keystore.b64
```

## قرار عدم التدوير التلقائي

المفتاح المضمّن سابقاً يبقى في Git كتاريخ توافق فقط. تغيير المفتاح دون خطة يمنع تحديث النسخ المثبتة. استخدم **نفس** المفتاح داخل Secrets إن أردت استمرار التحديث فوق التطبيقات الحالية.

## تحقق القبول

- [ ] الأسرار الأربعة موجودة في المستودع
- [ ] `workflow_dispatch` على `main` يبني APK موقّعاً
- [ ] سجلات CI لا تطبع كلمة مرور أو محتوى المفتاح
- [ ] Application ID ما زال `com.kayan.net_app`
- [ ] APK الجديد يحدّث النسخة المثبتة إذا كان المفتاح هو نفسه
