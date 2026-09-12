# تقرير التحقق البصري والتكامل — Dashboard والثيم

**Commit المرجع:** `26ea5d1dcd47efd7348faaac810befc0e62e73fc`  
**فرع Hardening:** `hardening/core-flow-p0-20260912`  
**حالة `main`:** ما زال عند `26ea5d1dcd47efd7348faaac810befc0e62e73fc` ولم يتم الدمج.

## نطاق المرحلة

هذه المرحلة مخصصة لـ Core Reliability فقط. لم يتم تعديل Dashboard Navigation، ولم يبدأ Post-v1.

## حالة التحقق

تم إصلاح مسار Core Business Flow ليعتمد على القرار التجاري المؤكد: مبلغ التحويل يطابق فئة CardCategory الموجودة فعليًا في الـCatalog، ثم يتم حجز كرت، إرسال تفاصيله عبر `MessageSender`/`NativeMessageSender`، وتثبيت حالة التسليم في Audit قبل إكمال الـSale المالي بنفس `operationId`.

التحقق النهائي يجب أن يعتمد على أحدث GitHub Actions Run على رأس الفرع، وليس على نتائج Runs أقدم.

```text
dart analyze lib test             → يجب أن PASS على أحدث HEAD
flutter analyze --no-fatal-infos  → يجب أن PASS على أحدث HEAD
flutter test                      → يجب أن PASS على أحدث HEAD
```

وجود معلومات deprecated في التحليل لا يُخفى، لكنها لا تمنع `flutter analyze --no-fatal-infos`.

## اختبارات Core الجديدة

تمت إضافة Drift integration coverage حقيقي لـ:

- Transfer 200 → matching category 200 → available card → delivery → Sale/Ledger/Audit.
- عدم وجود Category مطابقة.
- Category مطابقة بدون مخزون.
- Retry بنفس `operationId` بدون Sale/Ledger/SMS مكرر.
- فشل SMS وتحرير الحجز وإعادة المحاولة بنفس العملية.
- عمليتان متزامنتان لا تستهلكان الكرت نفسه مرتين.
- Reverse Sale مع ربط Transaction الأصلية.

## إثبات سلامة نطاق Dashboard Navigation

لم يتم إدخال أي تغيير في Dashboard Navigation ضمن إصلاح Core الحالي. بقية اختبارات Dashboard والتنقل تظل ضمن نطاقها السابق، ولا يُنسب أي فشل Core إلى Dashboard دون دليل.

## Android والـSMS

المسار الأصلي الموجود في التطبيق هو:

```text
MessageSender
  ↓
NativeMessageSender
  ↓
SmsBridge
  ↓
MethodChannel com.kayan.net/sms
  ↓
MainActivity.kt
  ↓
SmsManager.sendTextMessage
```

لا يوجد Fake SMS Provider في الإنتاج ولا تم إنشاء Provider تجاري بديل.

## Delivery State / Recovery

لعدم وجود جدول Delivery مستقل في البنية الحالية، يُستخدم `AuditLogRepository` لحفظ `sms_delivery_succeeded` مع `operationId` و`cardId` و`categoryId` و`reservationId`. في حال نجاح SMS ثم فشل Commit المالي، يستخدم Recovery هذا الحدث لإكمال نفس الحجز/البيع دون إعادة إرسال SMS.

## P0 Navigation

**P0 Navigation: مغلق وظيفيًا.**  
لم يُعدّل ضمن هذه المرحلة.

## Core Business Flow

**P0 Ready: غير مؤكد حتى الآن.** من ناحية التصميم، مسار `Transfer → Matching Category → Reservation → SMS Delivery → Reserved Sale → Sold → Ledger → Audit` أصبح موصولًا داخل الـComposition Root باستخدام الخدمات الأصلية.

لكن لا يجوز إعلان P0 Ready قبل نجاح أحدث دورة كاملة على HEAD النهائي للفرع:

```text
dart analyze lib test
flutter analyze --no-fatal-infos
flutter test
```

وعندها فقط يمكن تسجيل Commit النهائي كمرشح للدمج. لا يوجد دمج إلى `main` قبل ذلك.
