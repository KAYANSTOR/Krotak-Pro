# Core Business Flow Audit

**Reference base:** `26ea5d1dcd47efd7348faaac810befc0e62e73fc`  
**Branch:** `hardening/core-flow-p0-20260912`  
**Main:** ما زال عند `26ea5d1dcd47efd7348faaac810befc0e62e73fc` ولم يتم الدمج.

## 1. التدفق الفعلي في الكود

```text
Android SMS Receiver
  ↓
SmsBridge / IncomingSmsEvent
  ↓
IncomingSmsHandler
  ↓
LocalMessageParser
  ↓
ParsedTransfer
  ↓
LocalCustomerIdentityResolver
  ↓
LocalTransferProcessor
  ↓
LocalCustomerBalanceService.credit
  ↓
TransactionRepository + AuditLogRepository
  ↓
IncomingMessage = processed / rejected / failed
```

ومسار البيع الموجود فعليًا منفصل:

```text
DirectSaleScreen
  ↓
LocalSaleService.sellFromBalance(operationId)
  ↓
LocalCustomerBalanceService.getBalance
  ↓
LocalCardInventoryService.reserveAvailableCard
  ↓
CardRepository.markSold
  ↓
TransactionRepository (sale-op:<operationId>)
  ↓
SaleRepository
  ↓
AuditLogRepository
```

والإرسال الأصلي الموجود في Android:

```text
SmsBridge.sendSms
  ↓
MethodChannel com.kayan.net/sms
  ↓
MainActivity.kt
  ↓
SmsManager.sendTextMessage
```

## 2. الخدمات والمستودعات المشاركة

### Incoming SMS
- `IncomingSmsHandler`
- `MessageRepository`
- `MessageParser`
- `TransferProcessor`

### Identity / Customer
- `LocalCustomerIdentityResolver`
- `CustomerRepository`

### Financial ledger
- `LocalCustomerBalanceService`
- `TransactionRepository`
- `AuditLogRepository`
- `DriftUnitOfWork`

### Inventory / Sale
- `LocalCardInventoryService`
- `CardRepository`
- `LocalSaleService`
- `SaleRepository`

### SMS transport
- `SmsBridge`
- Native Android `SmsManager`
- `MessageSender` موجود كـcontract فقط، ولا توجد implementation موصولة بالـCore Flow الحالي.

## 3. ما تم إصلاحه في Core Reliability

1. أزيلت هوية SMS القديمة المبنية على `hashCode + minute`.
2. أصبح للرسالة الصحيحة مفتاح ثابت مشتق من `sender + reference`، مع fallback حتمي للرسائل التي لا تملك reference.
3. `incoming_messages.external_reference` عليه unique index، مع re-check عند تعارض الإدخال لمنع معالجة SMS نفسها مرتين بسبب race.
4. `LocalTransferProcessor` لم يعد يفقد `rejected/failed` عندما يعمل الـbusiness transaction Rollback؛ الحالة النهائية تُحفظ بعد خروج المعاملة.
5. `LocalSaleService` يدعم `operationId` ثابتًا، ويمنع إنشاء Sale ثانية أو Ledger ثانية لنفس العملية.
6. Sale Ledger يستخدم مرجعًا ثابتًا `sale-op:<operationId>`.
7. Reverse Sale يحتفظ برابط المعاملة الأصلية.
8. أضيفت اختبارات Drift حقيقية للـrollback وSale idempotency.

## 4. الفجوة التجارية المثبتة

`LocalTransferProcessor` الحالي لا ينشئ Sale ولا يحجز Card؛ هو يعالج التحويل كـCredit إلى رصيد العميل.

`ParsedTransfer` الحالي لا يحمل `categoryId` أو معلومات كافية لتحديد فئة بطاقة تجارية دون اختراع قاعدة عمل جديدة.

`MessageSender` موجود كحد Domain صحيح، لكن لا توجد implementation مرتبطة به في Application composition. `SmsBridge` نفسه هو transport حقيقي، لكنه ليس Delivery abstraction مع state/retry/recovery داخل التدفق.

لذلك لا توجد إمكانية صحيحة لادعاء أن التدفق الحالي هو:

```text
Transfer → Credit → Reserve Card → Sale → Send SMS
```

حتى يتم تحديد مصدر فئة البطاقة/fulfillment بشكل صريح، وربط `MessageSender` بالـApplication مع حالة تسليم قابلة للاسترداد.

## 5. أقل تصميم متوافق مع البنية الحالية

لا حاجة إلى Provider بديل أو Fake Service.

الحد الأدنى الصحيح لاحقًا هو:

```text
MessageSender
    ↓
SmsBridge adapter
    ↓
Android SmsManager
```

وتكون العملية المالية منفصلة عن التسليم:

```text
Financial Commit
  = Sale + Ledger + Card State + Audit

Delivery State
  = pending → sent | failed
```

فشل SMS لا يعيد العملية المالية ولا ينشئ Sale ثانية. Recovery يعيد محاولة التسليم فقط باستخدام `operationId/messageId` الثابت.

لكن تنفيذ هذه الحدود الآن يحتاج أولًا إلى قرار تجاري موثق حول مصدر `categoryId`/فئة الكرت في التحويل؛ لا يوجد هذا الحقل في `ParsedTransfer` الحالي، ولا يجوز استنتاجه بالتخمين.

## 6. نتائج الاختبارات الموثقة حتى الآن

آخر CI مكتمل قبل أحدث دورة تصحيح:

```text
dart analyze lib test            → PASS
flutter analyze --no-fatal-infos → PASS
flutter test                     → 69 passed / 3 failed
```

تم تحديد الفشل الثلاثة وإصلاحها في الفرع:

- customer-missing test كان يستخدم phone غير صالح.
- dedupe assertion كانت تستخدم `.single` رغم وجود lookup أولي وإعادة lookup.
- typed `Result<Transaction>` داخل `LocalTransferProcessor` كان يحتاج تثبيتًا صريحًا.

بعد ذلك بدأت دورة CI جديدة للتحقق من رأس الفرع الحالي؛ نتيجتها النهائية لم تثبت بعد في وقت إنشاء هذا التقرير.

## 7. الحالة النهائية

**P0 Ready: NO.**

السبب ليس Dashboard Navigation وليس نقص اختبار شكلي. السبب أن التدفق التجاري الكامل Transfer → Sale → SMS Delivery غير موجود كمسار موحد قابل للاسترداد، وأن متطلبات تحديد فئة البطاقة وحالة التسليم ليست ممثلة حاليًا في العقود/التخزين بما يكفي لإكمالها دون اختراع منطق أعمال.

**قرار الدمج:** لا دمج إلى `main` قبل نجاح التحقق الكامل وبعد إغلاق الفجوة التجارية بتصميم مبني على قواعد العمل الفعلية.
