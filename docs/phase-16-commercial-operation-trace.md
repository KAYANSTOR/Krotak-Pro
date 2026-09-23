# المرحلة 16 — تتبع العملية التجارية

**الفرع:** `development/full-completion`  
**التاريخ:** 2026-09-23  
**مرجع الخطة:** `krotak-pro-full-completion-plan.md` §16

## المطلوب

لكل عملية حساسة يمكن تتبع: من، متى، ماذا، لأي عميل/نقطة بيع، أي كرت، أي فئة، أي رسالة، نتيجة الإرسال، السبب عند الفشل، ومفتاح Idempotency.

## ما نُفّذ

- توسيع `AuditLogRepository.search` للبحث في `entityId` و`action` و`payloadJson`.
- خدمة `CommercialOperationTraceService` تجمّع الأحداث وتستخرج `operationId` و`customerId` و`cardId` و`messageId`.
- شاشة إعدادات «تتبع عملية تجارية» تحت قسم الصيانة.
- اختبار Drift يغطي تجميع الأحداث من حمولة JSON.

## خارج النطاق هنا

- التحقق الميداني على جهاز حقيقي (قائمة المرحلة 8).
- تعبئة أسرار التوقيع.
