# Phase 2 — Message fingerprint (application-level, complete)

**تاريخ:** 2026-09-18  
**الحالة:** مكتمل على مستوى التطبيق (بدون عمود Drift إضافي)

## القرار

بدل انتظار `build_runner` لعمود `message_fingerprint`، المفتاح يُخزَّن في
`incoming_messages.external_reference` عبر `PaymentFingerprintService`،
مع الفهرس الفريد الموجود أصلًا:

`idx_incoming_messages_external_reference`

## الخوارزمية (`PaymentFingerprintService` v1)

1. إن وُجد مرجع محفظة/بنك بعد التحليل →  
   `pay:v1:ref:{source}:{reference}`
2. وإلا →  
   `pay:v1:amt:{source}:{currency}:{amount}:{identifier}:{body}`
3. بدون تحليل →  
   `pay:v1:body:{source}:{body}`

القناة (SMS vs إشعار) **ليست** جزءًا من المفتاح: نفس المرجع التجاري = حدث واحد.

## مسار الإدراج

`UnifiedPaymentEventEngine.ingest`:

1. parse
2. compute fingerprint
3. `findByExternalReference(key)` → إن وُجد: لا بيع مزدوج
4. حفظ الرسالة بـ `externalReference = key`
5. عند سباق إدراج: إعادة `findByExternalReference` والتعامل كـ idempotent

## عمود DB منفصل

**مؤجّل اختياريًا** — ليس شرط إطلاق. الفهرس الحالي على `external_reference`
يكفي لمنع التكرار المالي.

## قبول

- نفس SMS مرتين → عملية مالية واحدة
- SMS + إشعار بنفس المرجع → عملية واحدة
- مراجع مختلفة → عمليات مستقلة
