# تقرير التحقق البصري والتكامل — Dashboard والثيم

**Commit المرجع:** `26ea5d1dcd47efd7348faaac810befc0e62e73fc`  
**فرع التحقق:** `hardening/core-flow-p0-20260912`  
**Dashboard Navigation:** مغلق قبل هذه المرحلة، ولم تُعدل ملفات التنقل ضمن هذه المرحلة.

## نتيجة الاختبارات والتحليل

```text
Local environment → لا يوجد checkout/Flutter toolchain قابل للتنفيذ من جلسة العمل الحالية.
GitHub Actions CI → بدأ على Pull Request #1، وحاليًا ما يزال قيد التنفيذ عند تجهيز Flutter.

flutter test                    → لم تظهر نتيجة نهائية بعد.
dart analyze lib test           → لم تظهر نتيجة نهائية بعد.
flutter analyze --no-fatal-infos → لم تظهر نتيجة نهائية بعد.
```

**ممنوع اعتبار الحالة ناجحة قبل اكتمال CI وظهور نتيجتي Analyze وUnit tests بنجاح.**

## إثبات سلامة نطاق Dashboard Navigation

المقارنة بين `78f5837` و`26ea5d1` تُظهر أن تغييرات هذه الفترة اقتصرت على:

- `lib/ui/home_shell.dart`
- `lib/ui/screens/dashboard_screen.dart`
- `test/widget/dashboard_navigation_test.dart`
- `test/widget/net_components_test.dart`
- هذا التقرير

ولا تشمل `Domain` أو `Database` أو `Repositories` أو `Services`. لذلك لا توجد صلاحية لنسبة أي فشل خدمات إلى تغييرات Dashboard Navigation دون دليل آخر.

## Core Business Flow Hardening

تم تنفيذ إصلاحات على الفرع للتحقق من:

1. إزالة هوية SMS المبنية على `hashCode + minute` واستبدالها بمفتاح ثابت مشتق من sender/reference أو sender/body.
2. الحفاظ على حالة `rejected/failed` بعد Rollback بدل فقدانها داخل نفس المعاملة.
3. إضافة `operationId` ثابت للبيع لمنع تكرار Sale/Ledger عند إعادة المحاولة.
4. الحفاظ على رابط معاملة البيع الأصلية عند Reverse Sale في مسار `operationId`.
5. إضافة اختبارات Drift حقيقية لمسار idempotency وrollback/recovery.

## الأجهزة / Android

| البيئة | النتيجة |
|---|---|
| Android Emulator | غير متحقق |
| `flutter build apk` | غير متحقق في هذه المرحلة |
| Android SDK | غير متاح في جلسة العمل الحالية |

## حالة P0 Navigation

**P0 Navigation: مغلق وظيفيًا حسب الكود والاختبارات المضافة سابقًا.**  
ولم يُعاد فتحه أو تعديله ضمن Hardening الحالي.

## حالة Core Business Flow

**غير P0 Ready بعد.** السبب الحالي ليس فشلًا مثبتًا في الاختبارات، بل أن التحقق التنفيذي الكامل لم يكتمل بعد، كما أن مسار `LocalTransferProcessor` الحالي ما زال يفصل تحويل الرصيد عن عملية البيع/إرسال SMS، ولا توجد في المعمارية الحالية خدمة إرسال SMS تجارية مدمجة داخل هذا المسار يمكن إضافتها بأمان دون اختراع طبقة بديلة.

**القرار:** لا دمج إلى `main` ولا إعلان نجاح نهائي قبل ظهور CI النهائي وإغلاق الفجوة المتبقية في التدفق الأساسي بناءً على الخدمات الموجودة فعليًا.
