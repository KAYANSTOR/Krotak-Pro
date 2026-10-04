# تكامل الإشعارات الحية عبر FCM

## ما تم تنفيذه

- تطبيق Flutter يهيئ Firebase اختياريًا من خلال `--dart-define`.
- الاشتراك في Topic عام: `krotak_all_users`.
- معالجة رسائل FCM في foreground/background.
- قناة Android باسم `krotak_admin` وأيقونة `ic_stat_stock`.
- لوحة الإدارة تنشئ مستندًا في `notification_requests` بدل اعتبار الكتابة إلى Firestore إرسالًا ناجحًا.
- Cloud Function باسم `dispatchNotificationRequest` ترسل عبر FCM وتكتب حالة التسليم.
- قواعد Firestore تمنع العميل من إنشاء طلبات الإرسال، وتسمح للمشرفين بقراءة سجلات التسليم.

## إعداد بناء التطبيق

مرر إعدادات مشروع Firebase العامة وقت البناء، ولا تضع Service Account داخل APK:

```bash
flutter pub get
flutter build apk --release \
  --dart-define=KROTAK_FIREBASE_API_KEY=... \
  --dart-define=KROTAK_FIREBASE_APP_ID=... \
  --dart-define=KROTAK_FIREBASE_PROJECT_ID=... \
  --dart-define=KROTAK_FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=KROTAK_FIREBASE_STORAGE_BUCKET=...
```

بدون هذه القيم يستمر التطبيق في وضعه المحلي الحالي، ولا يحاول الاتصال بـ Firebase.

## نشر الوظيفة والقواعد

من مجلد لوحة الإدارة وبعد تسجيل الدخول إلى Firebase واختيار المشروع الصحيح:

```bash
cd functions && npm install && cd ..
firebase use <PROJECT_ID>
firebase deploy --only functions:dispatchNotificationRequest,firestore:rules
```

لا تُشغّل النشر قبل التأكد من أن المشروع المختار هو مشروع Krotak الصحيح.

## الإرسال العام

تكتب لوحة الإدارة طلبًا مثل:

```json
{
  "audienceType": "global",
  "title": "عنوان",
  "body": "نص الإشعار",
  "data": { "route": "/account-notifications" },
  "status": "queued"
}
```

تقوم الوظيفة بإرساله إلى Topic `krotak_all_users`.

## الإرسال لمستخدم محدد

المسار المدعوم في الوظيفة هو:

```text
users/{uid}/devices/{tokenHash}
```

ويجب أن يكتب تطبيق Android Token بعد اكتمال تسجيل دخول الحساب السحابي باستخدام جلسة Firebase موثوقة. التسجيل العام في Topic يعمل الآن، أما التوجيه لمستخدم محدد فيتطلب ربط خدمة الحساب الحالية بعملية upsert للـToken؛ لا يجوز تخزين Token مجهول ثم نسبته إلى مستخدم بالاعتماد على قيمة محلية.

## ملاحظات التحقق

- بناء لوحة الإدارة ينجح باستخدام `npm run build`.
- Cloud Function تمر بفحص `node --check`.
- لم يتم نشر Cloud Function أو قواعد Firebase من هذه البيئة؛ النشر فعل خارجي يعتمد على مشروع Firebase وصلاحياته.
- لا يوجد في الملفات المضافة Service Account أو مفتاح Admin.
