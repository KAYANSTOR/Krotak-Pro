# المرحلة 10 — تحقق تسليم SMS (Sent + Delivered)

**التاريخ:** 2026-09-22  
**المصدر:** بند أ3 في `docs/audit-2026-09-21-ui-and-message-logic.md`  
**الحالة:** منفّذ في الكود

## المشكلة
الإرسال كان ينتظر نتيجة الراديو (`SMS_SENT`) فقط، و`deliveredIntent` كان `null`.
لا يمكن التمييز بين «قبلتها الشريحة» و«وصلت للجهاز المستهدف»، ولا تُسجَّل فشل التسليم.

## ما نُفّذ
1. `PendingIntent` مستقل لـ `SMS_DELIVERED` بجانب `SMS_SENT` (رسالة واحدة ومتعددة الأجزاء).
2. قناة أحداث `com.kayan.net/sms_outbound` تبلغ Flutter بنتيجة الناقل دون انتظارها داخل MethodChannel (التسليم قد يتأخر دقائق).
3. `SmsSendReceipt` يفسّر خريطة `{sent, requestId, to}` مع بقاء التوافق مع `true` القديم.
4. `OutboundSmsDeliveryHandler` يكتب Audit فقط:
   - `sms_delivered`
   - `sms_delivery_failed`
5. فشل التسليم **لا يعكس** عملية مالية ولا يعيد بيع الكرت. إعادة المحاولة تبقى مسار الإرسال الحالي.

## معيار القبول
- نجاح الراديو = نجاح `send` للطابور.
- تقرير التسليم يظهر في سجل التدقيق مرتبطًا بـ `requestId`.
- لا تغيير في قواعد الدفتر.

## المتبقي جهاز
تشغيل قائمة `docs/phase-8-device-verification-checklist.md` والتحقق أن تقرير التسليم يصل على جهاز حقيقي (بعض الشركات لا ترسل Delivery Report).
