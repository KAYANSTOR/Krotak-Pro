# توقيع التطبيق وتحديثه بدون إلغاء التثبيت

## لماذا تظهر «حزمة التثبيت لا تتوافق»؟

أندرويد يرفض تثبيت APK فوق تطبيق موجود إذا **اختلفت شهادة التوقيع**.

| النسخة المثبّتة الآن | التحديث الجديد | النتيجة |
|---------------------|----------------|---------|
| موقّع بمفتاح الإصدار (CI / key.properties) | نفس المفتاح | ✅ تحديث فوقه |
| موقّع بمفتاح الإصدار | debug أو مفتاح آخر | ❌ لا تتوافق |
| debug (`flutter run` / بناء بلا key.properties قديماً) | مفتاح الإصدار | ❌ لا تتوافق |
| artifact من PR (مفتاح ci-validation ليومين) | مفتاح الإصدار | ❌ لا تتوافق |

هذا **ليس** عطل في الكود التجاري؛ هو حماية أندرويد ضد استبدال التطبيق بنسخة من مصدر آخر.

## القاعدة الذهبية

**كل APK يصل لأجهزة الإنتاج يُوقَّع بنفس المفتاح التجاري فقط.**

- CI على `main` → GitHub Secrets (`APK_KEYSTORE_B64` …)
- بناء محلي للتوزيع → `android/key.properties` + `android/app/keystore/upload.jks` **نفس** المفتاح

## إعداد البناء المحلي (مرة واحدة)

1. من GitHub → Settings → Secrets انسخ قيم:
   - `APK_KEYSTORE_B64` → فكّ Base64 إلى الملف:
     `android/app/keystore/upload.jks`
   - `APK_KEY_ALIAS`, `APK_KEYSTORE_PASSWORD`, `APK_KEY_PASSWORD`
2. أنشئ `android/key.properties` من المثال:

```properties
storeFile=keystore/upload.jks
storeType=PKCS12
keyAlias=...
storePassword=...
keyPassword=...
```

3. ابنِ:

```bash
flutter build apk --release
```

بدون `key.properties` يفشل البناء الآن برسالة واضحة (بدلاً من توقيع debug صامت).

للاختبار فقط على جهاز تطوير:

```bash
flutter build apk --release -PallowDebugRelease=true
```

## إن كانت النسخة الحالية على الجهاز موقّعة بمفتاح خاطئ

لا يوجد حل سوى **إلغاء تثبيت مرة واحدة**، ثم تثبيت APK موقّع بالمفتاح التجاري، وبعدها كل التحديثات تعمل فوقه بدون حذف بيانات لاحقاً.

> احفظ نسخة احتياطية `.znet` من داخل التطبيق قبل الإلغاء إن لزم.

## versionCode

`pubspec.yaml` → `version: x.y.z+CODE` — يجب أن يزيد `CODE` مع كل تحديث يُنشر.
حالياً التوافق الأهم هو **المفتاح**؛ ثم رقم الإصدار.

## التحقق من شهادة APK

```bash
# بصمة الشهادة (يجب أن تتطابق بين المثبّت والجديد)
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk
```

على الجهاز (بعد تفعيل USB): قارن `dumpsys package com.kayan.net_app | grep signatures` إن لزم.
