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
- تقرير: [phase-7-cards-visual-close.md](phase-7-cards-visual-close.md)

### Phase 9 — البيع المباشر والعروض (2026-09-17) ✅ برمجيًا
- بيع مباشر: نقدي / آجل / هدية / نقطة بيع عبر Domain.
- عروض: إنشاء + تعديل + تفعيل/تعطيل + حذف من الكتالوج المحلي.
- تقرير: [phase-9-direct-sale-offers.md](phase-9-direct-sale-offers.md)

### Phase 10 — الصيانة وفحص النظام (2026-09-17) ✅ برمجيًا
- فحص النظام + تنظيف السجلات على `KayanPalette`.
- تقرير: [phase-10-maintenance-system-check.md](phase-10-maintenance-system-check.md)

### Phase 11 — تحقق جهاز نهائي + APK (2026-09-17) ✅ برمجيًا / 🟡 بانتظار جهاز حقيقي
- بوابات تدقيق بصري للكروت والتقارير والبيع المباشر والعروض وفحص النظام.
- إصدار `1.0.11+11` + CI release APK.
- تقرير: [phase-11-final-device-verification-apk.md](phase-11-final-device-verification-apk.md)

## المرحلة التالية — Phase 12 (جهاز فقط)

**الحالة:** محظورة — لا يُنفّذ برمجيًا ولا تُخترع نتائج جهاز.

1. تثبيت APK `1.0.11+11` على جهاز Android حقيقي.
2. تأكيد بصري لشاشات الكروت والتقارير والعروض والبيع المباشر وفحص النظام (فاتح + داكن).
3. تشغيل بوابات التحقق وحفظ حزمة الأدلة من شاشة تحقق الجهاز.
4. لا يُعتبر `readyForRelease` إلا بعد الحزمة المصدّرة من الجهاز.

مرجع: NET-POST-V1-MASTER-PLAN + خطة-المطابقة-100 — GitHub مصدر الحقيقة.

### UX Screens Refresh — واجهات 1.0.9 على نمط Z Net (2026-09-18) ✅ برمجيًا

> UI-only: صفر تغيير على المنطق/الخدمات/قواعد البيانات/المسارات. كل الاستدعاءات
> الحالية (`sellManual`، `CustomerService.create`/`addIdentifier`، `findByIdentifier`)
> كما هي حرفيًا — نفس الـoperationId ونفس التوقيعات.

1. **بيع مباشر (يدوي)** — إعادة تصميم كاملة على نمط الصورة المرجعية.
2. **إنشاء حساب مشترك جديد**.
3. **منتقي جهات الاتصال**.
4. **نظام المظهر الثلاثي**.
5. **ورقة مخزون الكروت**.

### إغلاق اتساق الهوية البصرية — الجولة الختامية (2026-09-18) ✅ برمجيًا

**بانتظار جهاز حقيقي:** التدقيق البصري النهائي (فاتح + داكن) وحزمة أدلة لقطات الشاشات — لا تُخترع نتائج جهاز.

### توحيد البطاقات والحالات المتبقية (2026-09-18) ✅ برمجيًا جزئيًا

> UI-only. لا تغيير على Domain/Data/Application/Platform.

- `FailedMessagesScreen`: استبدال `Card` الخام بـ `NetSurfaceCard`.
- `WalletsPosScreen`: الحالة الفارغة عبر `AsyncEmptyView` وبطاقة نقطة البيع عبر `NetSurfaceCard`.
- المرحلة الرسمية التالية تبقى Phase 12 (جهاز فقط) — لا تُخترع نتائج جهاز.
