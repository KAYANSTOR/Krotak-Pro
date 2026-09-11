# Core Business Flow Audit

**Reference base:** `26ea5d1dcd47efd7348faaac810befc0e62e73fc`  
**Branch:** `hardening/core-flow-p0-20260912`  
**Main:** ما زال عند `26ea5d1dcd47efd7348faaac810befc0e62e73fc` ولم يتم الدمج.

## 1. التدفق الفعلي بعد القرار التجاري

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
Find active CardCategory where faceValue == transfer amount
  ↓
LocalCardInventoryService.reserveAvailableCard
  ↓
LocalCustomerBalanceService.credit(reference = transfer reference)
  ↓
MessageSender / NativeMessageSender
  ↓
SmsBridge → Android SmsManager
  ↓
Audit: sms_delivery_succeeded
  ↓
ReservedSaleService / LocalSaleService.completeReservedSale
  ↓
CardRepository.markSold
  ↓
SaleRepository + TransactionRepository
  ↓
Audit: sale completed
  ↓
IncomingMessage = processed
```

Recovery after a successful SMS but failed financial commit follows the persisted `sms_delivery_succeeded` audit state and completes the same reservation/sale without sending another SMS.

## 2. الخدمات والمستودعات المشاركة

### Incoming SMS
- `IncomingSmsHandler`
- `MessageRepository`
- `MessageParser`
- `TransferProcessor`

### Identity / Customer
- `LocalCustomerIdentityResolver`
- `CustomerRepository`

### Category / Inventory
- `CardCategoryRepository`
- `LocalCardInventoryService`
- `CardRepository`
- `CardCategory.faceValue`

### Financial ledger / Sale
- `LocalCustomerBalanceService`
- `LocalSaleService`
- narrow `ReservedSaleService` boundary
- `SaleRepository`
- `TransactionRepository`
- `AuditLogRepository`
- `DriftUnitOfWork`

### SMS transport
- `MessageSender`
- `NativeMessageSender`
- `SmsBridge`
- Android `SmsManager`

## 3. ما تم إصلاحه

1. أزيلت هوية SMS غير الثابتة المبنية على `hashCode + minute`.
2. أصبح مفتاح SMS ثابتًا من `sender + reference` مع fallback حتمي إلى `sender + canonical body`.
3. `incoming_messages.external_reference` عليه unique index، مع re-check بعد insert race.
4. حالات `rejected/failed` تُحفظ خارج rollback المالي.
5. `LocalSaleService` يمنع تكرار Sale/Ledger باستخدام stable `operationId`.
6. Sale Ledger يستخدم `sale-op:<operationId>`.
7. Reverse Sale يحتفظ بمرجع المعاملة الأصلية.
8. تم ربط `NativeMessageSender` فعليًا داخل `AppContainer`.
9. تم اعتماد اختيار الفئة من Catalog الموجود فعليًا حسب exact amount + currency؛ لا `categoryId` ثابت ولا Category جديدة.
10. تم إضافة حجز ثابت مشتق من `operationId`، بحيث يكون الحجز جزءًا من نفس عملية الاسترداد.
11. أضيفت `ReservedSaleService` كحد ضيق لإكمال الكرت المحجوز بعد نجاح الإرسال دون حجز ثانٍ.
12. يتم تسجيل `sms_delivery_succeeded` قبل إكمال الـSale، ويُستخدم كدليل Recovery لمنع إعادة إرسال نفس بيانات الكرت.

## 4. الحالات التجارية

### Amount matched + card available
```text
200
→ Category.faceValue = 200
→ Reserve card
→ Credit transfer idempotently
→ Send card credentials
→ Persist delivery success
→ Complete reserved sale
→ Sold + Ledger + Audit
```

### No matching category
`unmatched_amount` → رفض قابل للتدقيق، بدون Credit أو Reservation أو Sale.

### Matching category but no card
`out_of_stock` → رفض/حالة واضحة، بدون Credit أو Sale.

### SMS failure
`failed` + `sms_delivery_failed` → تحرير الحجز، ولا Sale ثانية. إعادة المحاولة بنفس operationId تعيد المحاولة على نفس العملية.

### Delivery success then sale failure
`failed` + `sms_delivery_succeeded` + `transfer_sale_commit_failed` → لا يُعاد SMS. Recovery يعيد امتلاك نفس البطاقة إن بقيت قابلة للاسترداد ثم يكمل Sale بنفس operationId.

### Duplicate / retry
الـLedger المرجعي `sale-op:<operationId>` هو نقطة idempotency قبل أي Credit/Reservation جديد. نفس العملية لا تنتج Sale أو Ledger ثانية.

## 5. التزامن وRace Condition

حجز الكرت في `LocalCardRepository.reserve` يتم عبر تحديث شرطي على `status = available`. لذلك لا يمكن لعمليتين متزامنتين أن تنجحا في حجز نفس الكرت؛ العملية الخاسرة تحصل على `card_not_available`/`out_of_stock` ولا تتابع إلى Credit أو Sale.

## 6. Reverse Sale

البيع المكتمل يحتفظ بمعرف العملية نفسه في `Sale.id`. عند `reverseSale` تتم استعادة البطاقة، إنشاء Transaction من نوع `reversal`، وربطها بـ`relatedTransactionId` للـSale Ledger الأصلي. لا ينشئ Reverse عملية بيع جديدة.

## 7. نتائج التحقق

آخر دورة مكتملة قبل إغلاق هذه المرحلة كانت:

```text
dart analyze lib test            → PASS
flutter analyze --no-fatal-infos → PASS
flutter test                     → 69 passed / 3 failed
```

تم بعد ذلك تعديل تدفق `Transfer → Category → Reservation → SMS → Reserved Sale` وإضافة اختبارات Drift جديدة تغطي:

- amount → matching category
- no matching category
- matching category without stock
- stable-operation retry
- SMS failure and retry
- concurrent card consumption
- Reverse Sale + original ledger relation

**نتيجة CI لهذه التغييرات الجديدة يجب اعتمادها فقط من أحدث Run على رأس الفرع.** لا تعتبر الاختبارات ناجحة قبل ظهور نتيجة GitHub Actions النهائية.

## 8. الفجوات المتبقية

الفجوة المتبقية الرئيسية هي حدود ضمان Recovery بعد مدة تتجاوز TTL للحجز: إذا أصبح الكرت المباع عبر SMS متاحًا ثم تم أخذه بواسطة عملية تجارية أخرى، يتوقف Recovery ولا يخترع Card بديلًا ولا يعيد إرسال بيانات جديدة. هذا سلوك مقصود لحماية الاتساق.

كما أن `MessageSender` التجاري ما زال يعتمد على الإرسال الأصلي في الجهاز عبر `SmsManager`; لا يوجد Provider تجاري خارجي داخل المشروع، ولم يتم اختراع Provider جديد.

## 9. P0 Ready

**P0 Ready: NO حتى الآن.**

السبب الحاكم هو ضرورة نجاح أحدث CI بالكامل وإثبات الاختبارات الجديدة على الرأس النهائي. من ناحية التصميم، الفجوة `Transfer → Category → Reservation → SMS → Sale → Ledger → Audit` أصبحت ممثلة في الـCore الحالي دون إنشاء Architecture موازية.

**قرار الدمج:** لا دمج إلى `main`، ولا تغيير في `26ea5d1`، حتى ينجح `dart analyze lib test` و`flutter analyze --no-fatal-infos` و`flutter test` على أحدث HEAD.
