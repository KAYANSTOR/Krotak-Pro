# NET Flutter

إعادة بناء تطبيق **NET** لأصحاب ومزودي شبكات الإنترنت باستخدام Flutter وDart.

هذا المستودع مستقل عن مستودع Kotlin المرجعي. مستودع Kotlin يُستخدم كمرجع للتصميم وتدفقات الواجهات فقط، بينما تُبنى قاعدة البيانات والمنطق التجاري ومعالجة SMS من الصفر وفق مواصفات NET المعتمدة.

## الحالة الحالية

المشروع في مرحلة التهيئة الأولى. تم إنشاء هيكل Flutter Android قياسي، ولم تُنقل أي شاشة إنتاجية أو تُضاف بيانات تجريبية. المرحلة التالية هي تثبيت قرارات المجال وقاعدة البيانات قبل تنفيذ الواجهات.

## المبادئ

- Local-first والعمل اليومي دون الاعتماد على الإنترنت.
- معاملات مالية ذرية وقابلة للتدقيق.
- Flutter للواجهة والمنطق المشترك.
- Android Native Bridge لمعالجة SMS والخدمات الخلفية عند الحاجة.
- منع Mock Data في نسخة الإنتاج.
- تنفيذ كل ميزة من Domain إلى Database إلى Service إلى UI إلى Tests.

## المتطلبات

- Flutter 3.47.3 أو إصدار stable متوافق.
- Dart 3.13.3 أو إصدار متوافق.
- Android Studio وAndroid SDK.
- JDK متوافق مع نسخة Flutter/Gradle المستخدمة.

## أوامر التحقق

```bash
flutter pub get
flutter analyze
flutter test
```

## المراجع

- مستودع الواجهات المرجعي: https://github.com/KAYANSTOR/kayan-android-kotlan
- خطة التنفيذ: [`docs/implementation-plan.md`](docs/implementation-plan.md)
- خريطة النقل: [`docs/migration-map.md`](docs/migration-map.md)
