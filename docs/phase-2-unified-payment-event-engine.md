# Post-V1 Phase 2 — Unified Payment Event Engine

**التاريخ:** 2026-09-13  
**المستودع:** KAYANSTOR/Krotak-Pro  
**الحالة:** منفَّذ في Domain + Application + Tests

## الهدف

مسار إدخال واحد لكل ملاحظة دفع (SMS، إشعار محفظة لاحقًا، إدخال يدوي) قبل أي قرار تجاري.

```text
PaymentEvent (channel + source + raw body)
  -> MessageParser
  -> PaymentFingerprintService
  -> persist IncomingMessage (externalReference = fingerprint)
  -> PD-07 auto-process gate
  -> TransferProcessor
```

## قواعد البصمة (v1)

- المرجع المستخرج من القالب يسبق أي شيء: `pay:v1:ref:{source}:{ref}`
- بلا مرجع: `pay:v1:amt:{source}:{currency}:{minor}:{ident}:{body}`
- بلا تحليل: `pay:v1:body:{source}:{body}`
- القناة ليست جزءًا من المفتاح حتى لا يُكرَّم نفس التحويل مرتين إذا وصل SMS وإشعار مع نفس المرجع.

## ما لم يُنفَّذ عمدًا (المرحلة 3+)

- Android Notification Listener
- جداول Drift جديدة / migration
- قوالب إنتاج لمحافظ محددة دون عينات حقيقية
