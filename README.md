# NET Flutter

إعادة بناء تطبيق **NET** لأصحاب ومزودي شبكات الإنترنت باستخدام Flutter وDart.

هذا المستودع مستقل عن مستودع Kotlin المرجعي. مستودع Kotlin يُستخدم كمرجع للتصميم وتدفقات الواجهات فقط، بينما تُبنى قاعدة البيانات والمنطق التجاري ومعالجة SMS من الصفر وفق مواصفات NET المعتمدة.

## الحالة الحالية

تم إنشاء هيكل Flutter Android قياسي، وأضيفت وثائق المشروع الرسمية. لم تُنقل أي شاشة إنتاجية بعد، ولم تُضف بيانات Mock أو منطق مالي غير موثق. المرحلة الحالية هي تثبيت المتطلبات والدومين وقاعدة البيانات قبل تنفيذ الواجهات.

## المبادئ

- Local-first والعمل اليومي دون الاعتماد على الإنترنت.
- معاملات مالية ذرية وقابلة للتدقيق.
- Flutter للواجهة والمنطق المشترك.
- Android Native Bridge لمعالجة SMS والخدمات الخلفية عند الحاجة.
- منع Mock Data في نسخة الإنتاج.
- تنفيذ كل ميزة من Domain إلى Database إلى Service إلى UI إلى Tests.

## الوثائق الأساسية

- [خطة التنفيذ الكاملة](docs/master-plan.md)
- [المواصفات الوظيفية لـ NET](docs/net-functional-specification.md)
- [تحليل مستودع Kotlin المرجعي](docs/kotlin-reference-analysis-ar.md)
- [خطة التنفيذ الأولية](docs/implementation-plan.md)
- [خريطة نقل الشاشات](docs/migration-map.md)

## المستودع المرجعي

https://github.com/KAYANSTOR/kayan-android-kotlan

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
