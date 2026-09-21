# المرحلة 7 — توقيع الإصدار عبر GitHub Secrets

**التاريخ:** 2026-09-21  
**الفرع:** `development/full-completion`  
**الحالة:** مسار CI جاهز — ينتظر إضافة الأسرار في إعدادات المستودع

## القرار

بناء APK الإصدار في CI يعتمد على GitHub Secrets فقط. لا يُستخدم ملف `android/signing/*.b64` داخل Runner.

الملف المودَع سابقًا في Git يبقى لأغراض التوافق المحلي حتى يقرر المالك تدوير المفتاح. تدوير مفتاح الإنتاج دون خطة يمنع تحديث الأجهزة المثبّت عليها النسخة الحالية.

## الأسرار المطلوبة

من GitHub → Settings → Secrets and variables → Actions:

| السر | الغرض |
|------|--------|
| `APK_KEYSTORE_B64` | محتوى JKS/PKCS12 بعد `base64 -w 0` |
| `APK_KEYSTORE_PASSWORD` | كلمة مرور المخزن |
| `APK_KEY_PASSWORD` | كلمة مرور المفتاح |
| `APK_KEY_ALIAS` | اسم الـ alias |

توليد Base64 محليًا:

```bash
base64 -w 0 path/to/krotak-release.jks > krotak-keystore.b64
```

## سلوك CI

1. يفشل `build-apk` فورًا إذا نقص أي سر.
2. يفك Base64 داخل Runner فقط.
3. يكتب `android/key.properties` مؤقتًا.
4. يبني `flutter build apk --release`.
5. يحذف الملفات المؤقتة حتى عند الفشل.
6. لا يطبع قيم الأسرار.

## البناء المحلي

بدون `android/key.properties` يوقّع Gradle الإصدار بمفتاح debug (سلوك موجود مسبقًا).
للتوقيع بنفس مفتاح الإنتاج محليًا أنشئ `android/key.properties` خارج Git.

## ما لا يُنجَز تلقائيًا

- إنشاء الأسرار في GitHub (صلاحية المالك).
- حذف `android/signing/net-upload.jks.b64` قبل قرار التدوير.
- التحقق على جهاز حقيقي أن APK المحدّث يُثبَّت فوق النسخة الحالية (مرحلة 8).
