# NET Flutter

إعادة بناء تطبيق **NET** لأصحاب ومزودي شبكات الإنترنت باستخدام Flutter وDart.

هذا المستودع مستقل عن مستودع Kotlin المرجعي. مستودع Kotlin يُستخدم كمرجع للتصميم وتدفقات الواجهات فقط، بينما تُبنى قاعدة البيانات والمنطق التجاري ومعالجة SMS من الصفر وفق مواصفات NET المعتمدة.

## الحالة الحالية

تم إنشاء هيكل Flutter Android قياسي، وإضافة الوثائق الرسمية، ثم بناء أول طبقات Domain وقاعدة البيانات المحلية وRepositories واختباراتها. لم تُنقل أي شاشة إنتاجية بعد، ولم تُضف بيانات Mock أو API أو معالجة SMS فعلية.

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
- [نموذج Domain الأولي](docs/domain-model.md)
- [مخطط قاعدة البيانات المحلية](docs/database-schema.md)
- [ميزات ما بعد الخطة الأولى](docs/post-v1-features.md)
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
