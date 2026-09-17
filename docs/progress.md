# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 17 — Promotion Reward Reversal (2026-09-16) ✅ في المستودع
- عكس مكافأة العرض عند reverseSale.
- تقرير: [phase-17-promotion-reward-reversal.md](phase-17-promotion-reward-reversal.md)

### Phase 18 — Device Measurement Evidence (2026-09-16) 🟡 منفذة في المستودع / بانتظار جهاز حقيقي
- أدلة المشغّل (ملاحظة + مقاييس + وقت) داخل `device_verification_gates` مع توافق للصيغة القديمة.
- تقرير: [phase-18-device-measurement-evidence.md](phase-18-device-measurement-evidence.md)

### Phase 19 — Device Verification Protocol (2026-09-16) ✅ برمجيًا / 🟡 بانتظار تشغيل جهاز
- `exportEvidencePack` لحزمة أدلة JSON قابلة للنسخ.
- تقرير: [phase-19-device-verification-protocol.md](phase-19-device-verification-protocol.md)

## خطة المطابقة 100%

### Phase 8.2–8.4 — التقارير وتسوية POS (2026-09-17) ✅ برمجيًا
- تقرير مبيعات حسب الفترة.
- حسابات نقاط البيع مع المستحق والعمولة والتسوية اليدوية/التلقائية.
- تقرير: [phase-8-reports-pos-settlement.md](phase-8-reports-pos-settlement.md)

### Phase 7 — شاشة الكروت (2026-09-17) ✅ برمجيًا
- فئات + استيراد فردي/دفعة + تذكرة + فلاتر + عمليات محجوز.
- نسخ السريال/السر، إنشاء فئة دون إغلاق عند الخطأ، تحميل الحالة المنتهية.
- تقرير: [phase-7-cards-visual-close.md](phase-7-cards-visual-close.md)

### Phase 9 — البيع المباشر والعروض (2026-09-17) ✅ برمجيًا
- بيع مباشر: نقدي / آجل / هدية / نقطة بيع عبر Domain.
- عروض: إنشاء + تعديل + تفعيل/تعطيل + حذف من الكتالوج المحلي.
- تقرير: [phase-9-direct-sale-offers.md](phase-9-direct-sale-offers.md)

## المتبقي

- تأكيد بصري على جهاز Android حقيقي لشاشة الكروت والتقارير والعروض والبيع المباشر.
- تشغيل بوابات التحقق على جهاز Android حقيقي وحفظ حزمة الأدلة.
- المرحلة 10: الصيانة وفحص النظام (تدقيق بصري).
- المرحلة 11: تحقق جهاز نهائي + APK.

مرجع: NET-POST-V1-MASTER-PLAN + خطة-المطابقة-100 — GitHub مصدر الحقيقة.
