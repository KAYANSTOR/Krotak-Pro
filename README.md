# NET Flutter

تطبيق Android لإدارة بيع الكروت والتحويلات عبر SMS — يعمل محلياً (Drift) مع جسر Native لاستقبال وإرسال الرسائل.

## المعمارية

```text
UI (Flutter)
  → AppContainer (composition root)
  → Domain services / use cases
  → Repositories → Drift SQLite
  → Android SmsReceiver + MethodChannel/EventChannel
```

المشروع مستقل عن مستودع Kotlin المرجعي. ذلك المستودع يستخدم كمرجع للتصميم وتدفقات الواجهات، بينما تُبنى قاعدة البيانات والمنطق التجاري ومعالجة SMS في هذا المشروع وفق المواصفات المعتمدة.

## الحالة الحالية

تم إنشاء هيكل Flutter Android، وإضافة الوثائق الرسمية، وطبقات Domain وقاعدة البيانات المحلية وRepositories، ثم بدأت مكونات الواجهة الأساسية والخدمات المحلية. ما تزال معالجة SMS الفعلية والتدفقات المالية الكاملة قيد التنفيذ، ولا تُستخدم بيانات Mock كبيانات إنتاج.

## المبادئ

- Local-first والعمل اليومي دون الاعتماد على الإنترنت.
- معاملات مالية ذرية وقابلة للتدقيق.
- Flutter للواجهة والمنطق المشترك.
- Android Native Bridge لمعالجة SMS والخدمات الخلفية عند الحاجة.
- منع Mock Data في نسخة الإنتاج.
- تنفيذ كل ميزة من Domain إلى Database إلى Service إلى UI إلى Tests.

## الوثائق الأساسية

- [خطة التنفيذ الكاملة](docs/master-plan.md)
- [تقرير مقارنة الخطة بالتنفيذ](docs/progress-audit-2026-09-11.md)
- [المواصفات الوظيفية لـ NET](docs/net-functional-specification.md)
- [تحليل مستودع Kotlin المرجعي](docs/kotlin-reference-analysis-ar.md)
- [نموذج Domain الأولي](docs/domain-model.md)
- [مخطط قاعدة البيانات المحلية](docs/database-schema.md)
- [ميزات ما بعد الخطة الأولى](docs/post-v1-features.md)
- [خطة التنفيذ الأولية](docs/implementation-plan.md)
- [خريطة نقل الشاشات](docs/migration-map.md)
- [سجل المراحل المكتملة](docs/progress.md)

## المستودع المرجعي

https://github.com/KAYANSTOR/kayan-android-kotlan

## التشغيل

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

صلاحيات SMS تُطلب من شاشة لوحة التحكم.

## الاختبار

```bash
flutter analyze
flutter test
```
