# إعداد حساب الشبكة وFirebase

تم ربط التطبيق بالمشروع الحقيقي:

- **Firebase Project ID:** `kroty-434e3`
- **Android package:** `com.kayan.net_app`
- **طريقة الاتصال:** Firebase Identity Toolkit وFirestore REST الرسميان عبر HTTPS.

> Web API Key وProject ID إعدادات عميل عامة وليسا أسراراً. حماية البيانات تكون من خلال Firebase Authentication وقواعد Firestore.

## قبل أول تشغيل

1. افتح Firebase Console للمشروع `kroty-434e3`.
2. من **Authentication → Sign-in method** فعّل **Email/Password**.
3. تأكد أن قاعدة Firestore منشأة في المنطقة المطلوبة.
4. انشر قواعد Firestore التي تسمح للمستخدم الموثق بإنشاء/قراءة وثيقته `users/{uid}` وبياناته الفرعية، وتسمح للمدير الموثق بإدارة المستخدمين والإشعارات.
5. فعّل حساب المدير في مجموعة `Admins/{uid}` كما هو موضح في دليل لوحة الإدارة.

## كيف يعمل تسجيل الرقم + كلمة المرور

Firebase لا يوفر طريقة «رقم هاتف + كلمة مرور» مباشرة. التطبيق يحافظ على تجربة المستخدم المطلوبة ويحوّل الرقم داخلياً إلى بريد تقني ثابت من الشكل:

```text
9677xxxxxxx@krotak.app
```

المستخدم لا يرى البريد التقني؛ يدخل رقم الهاتف وكلمة المرور فقط. المصادقة تتم عبر Firebase Auth الحقيقي، ووثيقة الحساب تُحفظ في:

```text
users/{uid}
networks/{uid}/_metadata/info
```

## بيانات الحساب

عند التسجيل، ينشأ الحساب تلقائياً بحالة:

- `is_active: true`
- `is_trial: true`
- `subscription_end_date`: وفق `app_settings/global_config.default_trial_days`
- اسم الشبكة ورقم الهاتف ووقت الإنشاء

وتقرأ لوحة الإدارة نفس الوثيقة لتوقيف الحساب أو تفعيله أو تحويله من تجريبي إلى رسمي.

## الإشعارات

- لحساب محدد: `users/{uid}/notifications/{notificationId}`
- إشعار عام: `app_settings/global_config/notifications/{notificationId}`

الحقول المطلوبة: `title`, `message`, `timestamp`، وللإشعار الخاص `is_read`.

## إعادة البناء

يمكن استخدام الإعداد الموجود داخل `lib/core/cloud_config.dart`، أو تمرير القيم وقت البناء:

```bash
flutter build apk --release \
  --dart-define=KROTAK_FIREBASE_API_KEY=... \
  --dart-define=KROTAK_FIREBASE_PROJECT_ID=kroty-434e3
```

ملف `android/app/google-services.json` محفوظ أيضاً باسم المسار القياسي للتوافق مع إعدادات Android المستقبلية.
