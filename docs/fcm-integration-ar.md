# تكامل الإشعارات الحية عبر FCM

## الحالة المطبقة على مشروع Firebase

- المشروع النشط: `kroty-434e3` (Kroty).
- تطبيق Android المسجل: `Krotak-pro` بالمعرّف `com.kayan.net_app`.
- قواعد Firestore المحدثة **منشورة فعليًا** على المشروع.
- إعداد العميل محفوظ في `android/app/google-services.json` (إعداد عام غير سري).
- Cloud Functions **غير منشورة**: مشروع `kroty-434e3` على خطة Spark، والخدمة ترفض النشر وتطلب الترقية إلى Blaze:

```text
Your project kroty-434e3 must be on the Blaze (pay-as-you-go) plan
to complete this command.
```

## ما تم تنفيذه في التطبيق

- تهيئة Firebase من `google-services.json`، مع إمكانية تجاوزها عبر `--dart-define`.
- الاشتراك في Topic عام: `krotak_all_users`.
- استقبال الإشعارات في foreground/background، وإظهارها محليًا أثناء استخدام التطبيق.
- قناة Android باسم `krotak_admin` وأيقونة `ic_stat_stock`.
- أي فشل في تهيئة Firebase لا يمنع إقلاع التطبيق المحلي.
- بعد جاهزية جلسة الحساب، يُحفظ Token في `users/{uid}/devices/{deviceId}` مع تحديثه عند تغيّره.
- النقر على إشعار يحمل `route: /account-notifications` يفتح صندوق إشعارات الإدارة، بما في ذلك الإقلاع من إشعار والتطبيق مغلق.

## ما تم تنفيذه في لوحة الإدارة

- زر الإرسال ينشئ طلبًا في `notification_requests` بدل اعتبار كتابة Firestore إرسالًا ناجحًا.
- Cloud Function `dispatchNotificationRequest` ترسل عبر FCM وتكتب حالة التسليم:
  `queued` / `sent` / `partial` / `failed` / `no_devices`.
- قواعد Firestore تمنع العميل من إنشاء الطلبات أو تعديل سجلات التسليم.

## حالة الربط الحالية

- الإرسال العام: جاهز برمجيًا عبر Vercel API إلى Topic `krotak_all_users`.
- الإرسال الموجه: جاهز برمجيًا بعد تسجيل الحساب؛ يعتمد على `users/{uid}/devices`.
- التحقق المتبقي: إعداد متغير `FIREBASE_SERVICE_ACCOUNT` في Vercel واختبار جهاز Android حقيقي.

## المتبقي لتفعيل الإرسال الفعلي

اختر أحد المسارين:

### المسار الأول: ترقية المشروع إلى Blaze

بعد الترقية من صفحة الاستخدام في Firebase Console، يُنشر ما يلي من مستودع لوحة الإدارة:

```bash
firebase use kroty-434e3
firebase deploy --only functions,firestore:rules
```

وتبقى تكلفة Cloud Functions ضمن الطبقة المجانية للاستخدام الخفيف.

### المسار الثاني: الإرسال اليدوي من Firebase Console

من دون ترقية، يمكن إرسال رسالة عامة من:

```text
Firebase Console → Messaging → New campaign → Android → Topic: krotak_all_users
```

يصل الإشعار إلى كل جهاز مشترك في Topic العام. هذا مسار يدوي ولا يربط طلبات لوحة الإدارة بالتنفيذ الآلي.

## الإرسال لمستخدم محدد

المسار المدعوم في الوظيفة:

```text
users/{uid}/devices/{tokenHash}
```

يكتب التطبيق الـToken بعد اكتمال تسجيل دخول الحساب السحابي بجلسة موثوقة، ولا ينسب Token مجهولًا إلى مستخدم اعتمادًا على قيمة محلية.

## التحقق

- `firebase_validate_security_rules` على قواعد Firestore: لا أخطاء.
- نشر Firestore: نجح (Job `1791157115302`).
- نشر Functions: مرفوض بسبب خطة Spark (Job `1791157434061`).
- بناء لوحة الإدارة وفحص Cloud Function: نجحا في GitHub Actions.
