# تقرير التحقق البصري والتكامل — Dashboard والثيم

**Commit المرجع:** `26ea5d1dcd47efd7348faaac810befc0e62e73fc`  
**فرع Hardening:** `hardening/core-flow-p0-20260912`  
**حالة `main`:** ما زال عند `26ea5d1dcd47efd7348faaac810befc0e62e73fc` ولم يتم الدمج.

## نطاق المرحلة

هذه المرحلة مخصصة لـ Core Reliability فقط. لم يتم تعديل Dashboard Navigation، ولم يبدأ Post-v1.

## نتيجة الاختبارات والتحليل

أحدث دورة CI مكتملة موثقة (`run #62`) وصلت إلى جميع خطوات التحقق:

```text
dart analyze lib test          → PASS
flutter analyze --no-fatal-infos → PASS
flutter test                   → 69 passed, 3 failed
```

الفشل الثلاثة في تلك الدورة كانت:

1. اختبار `LocalTransferProcessor` كان يمرر معرف هاتف غير صالح (`unknown`) ولذلك أعاد `invalid_phone_identifier`; تم تصحيح الاختبار ليستخدم رقمًا صالحًا غير مرتبط بعميل.
2. اختبار deduplication كان يستخدم `.single` رغم أن الـhandler يجري استعلام تحقق أولي ثم استعلامًا عند الإعادة؛ تم تصحيح التوقع ليُثبت أن المفتاح نفسه استُخدم مرتين.
3. كان هناك فشل typing داخل `LocalTransferProcessor` بسبب استنتاج `Failure<Object?>`؛ تم تثبيت نوع `Result<Transaction>` صراحة داخل `unitOfWork.run<Transaction>`.

بعد هذه الإصلاحات بدأت دورة CI جديدة على رأس الفرع الحالي، وما زالت قيد التنفيذ عند تاريخ تحديث هذا التقرير. لذلك لا تعتبر المرحلة ناجحة بعد.

## اختبارات Widget

في دورة `run #62` نجحت اختبارات واجهة Dashboard والتنقل:

- `dashboard_navigation_test.dart` — 4 اختبارات.
- `p1_navigation_smoke_test.dart` — 4 اختبارات.
- `net_components_test.dart` — 13 اختبارًا.
- `widget_test.dart` — اختبار واحد placeholder.

الإجمالي: **22 اختبار Widget ناجح**.

## إثبات سلامة نطاق Dashboard Navigation

المقارنة Git بين `78f5837` و`26ea5d1` تُظهر أن تغييرات Navigation كانت محصورة في ملفات UI والاختبارات والتقرير، ولم تشمل Domain/Database/Repositories/Services. وبالتالي لا تُنسب إخفاقات Core Services إلى Dashboard Navigation.

## Android والبيئة

| البيئة | النتيجة |
|---|---|
| GitHub Actions | متاح ويشغل Flutter/SQLite فعليًا |
| Flutter في CI | `3.47.4` |
| Ubuntu runner | `24.04.5 LTS` |
| SQLite development package | مثبت وناجح |
| Android Emulator | غير متاح للتحقق البصري هنا |
| Android SDK في جلسة العمل المحلية | غير متاح |
| APK build محلي | لم يُعتبر شرطًا لنجاح اختبارات Dart/Flutter الحالية |

## P0 Navigation

**P0 Navigation: مغلق وظيفيًا.**  
لم يُعدّل ضمن هذه المرحلة، واختبارات التنقل المخصصة نجحت.

## Core Business Flow

**Core Business Flow P0: غير مغلق بعد.** السبب المعماري المثبت هو أن `LocalTransferProcessor` ينتهي حاليًا عند Credit + Message State + Audit، بينما `LocalSaleService` مسار منفصل يحتاج `categoryId/operationId`، و`ParsedTransfer` الحالي لا يحمل فئة بيع. كما أن `MessageSender` موجود كـcontract فقط ولا توجد implementation مرتبطة به في الـApplication flow، بينما `SmsBridge` هو النقل الأصلي الفعلي.

لا يجوز إعلان P0 Ready قبل اكتمال واختبار ربط Transfer → Sale → Delivery State مع Recovery مستقل للتسليم.
