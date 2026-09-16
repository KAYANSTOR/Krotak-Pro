# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

انظر التفاصيل في نسخة المستودع السابقة. أضيفة Phase 18 أدناه.

### Phase 17 — Promotion Reward Reversal (2026-09-16) ✅ في المستودع
- عكس مكافأة العرض عند reverseSale.
- تقرير: [phase-17-promotion-reward-reversal.md](phase-17-promotion-reward-reversal.md)

### Phase 18 — Device Measurement Evidence (2026-09-16) 🟡 منفذة في المستودع / بانتظار جهاز حقيقي
- أدلة المشغّل (ملاحظة + مقاييس + وقت) داخل `device_verification_gates` مع توافق للصيغة القديمة.
- لا يُؤكَّد `bulk_import` أو `broadcast_rate` دون ملاحظة قياس.
- `recordImportMeasurement` / `recordBroadcastMeasurement` لتسجيل نتائج التشغيل.
- شاشة تحقق الجهاز تطلب الدليل وتعرضه.
- اختبارات: `test/services/device_verification_service_test.dart`
- تقرير: [phase-18-device-measurement-evidence.md](phase-18-device-measurement-evidence.md)

## المتبقي Post-V1 (الترتيب الرسمي)
لا بنود برمجية رسمية متبقية بعد Phase 18 سوى التشغيل على جهاز Android حقيقي: تأكيد بوابات Phase 12 مع أدلة القياس لبوابتي الاستيراد والبث.

مرجع: NET-POST-V1-MASTER-PLAN — GitHub مصدر الحقيقة؛ لا Local Only.
