# تقدم تنفيذ خطة NET

## التحقق (2026-09-12)

```text
CI على main (آخر تشغيل): success عند آخر hardening
dart analyze lib test  → يمر في CI
flutter test           → يمر في CI
```

تم إغلاق فجوة العقود والاختبارات التي وردت في تقرير 11 سبتمبر بعد سلسلة hardening للتدفق الأساسي.

**قرارات المنتج المعتمدة:** تُسجَّل في [product-decisions.md](product-decisions.md) وتُلغي أي تعارض لاحق مع Kotlin أو الافتراضات.

## ما اكتمل فعليًا

### Domain + محرك الأعمال
- عملاء، رصيد، مخزون FIFO، بيع + عكس، Parser + Identity Resolver + Transfer (6A)
- استعادة رسائل، تسوية، دمج حسابات، Audit، SMS Bridge
- **التدفق الأساسي (Amount → Category → Reserve → Credit → Send SMS → Complete Reserved Sale)** مع idempotency وrollback
- `ReservedSaleService` وربط `NativeMessageSender`
- `getTotalOutstanding` لرصيد إجمالي بدون N+1 (2026-09-12)

### المرحلة 6A (مكتملة)
- `TransferIdentifierType` وتصنيف phone/account/reference/name
- محرك قوالب موحّد `{ }` و `%`
- تطبيع الأرقام العربية
- `LocalCustomerIdentityResolver` مع Unresolved صريح و deliveryPhone
- `LocalTransferProcessor` يرفض دون تخمين ويسجّل Audit

### واجهات (P0 / P1)
- Dashboard / Customers / Inventory / Settings / Reports / DirectSale / TransactionsLog / WalletsPos: مربوطة ببيانات حقيقية + Loading/Empty/Error
- Offers / Help: placeholders صادقة
- ثيم Kayan + RTL + Bottom Navigation

### Dashboard — كرت الرصيد / Header / Alert / Metric Cards / بيع يدوي
- معتمدة PD-01…04 و PD-06 — انظر [product-decisions.md](product-decisions.md)

### إعدادات — S1/S2 منفَّذ (2026-09-12)
- أقسام PD-07 الستة + كروت + مفاتيح محفوظة محليًا
- كرت اسم الشبكة + Bottom Sheet (نص SMS المعتمد)
- المظهر light/dark عبر `themeModeNotifier`

### قرارات إعدادات النظام (معتمد 2026-09-12)
- PD-07 / PD-08
- **خطة التنفيذ المحدّثة (دفعة B):** [ui-build-plan-settings-help.md](ui-build-plan-settings-help.md) — تربط S3 Domain بالمعلّقة والمرفوضة والمخزون

### CI
- `.github/workflows/ci.yml` يشغّل analyze + test على كل push/PR — أخضر على main

## متبقٍ (بالترتيب الجذري)

1. **الدفعة B** — S0–S2✓. التالي مترابط: **B1 S3 Domain** → **B2 معلّقة** → **B3 مرفوضة** → B4 دفتر → B5–B7 كروت/فئات/استيراد → B8 مساعدة.
2. **منهجية مطابقة الواجهة (PD-05)** — مستمر لباقي الشاشات (محافظ، فوسك، محاكاة، قوالب عملاء = دفعة لاحقة).
3. **عينات قوالب SMS حقيقية** من المحافظ المعتمدة.
4. **اختبار جهاز حقيقي** لمسار SMS الكامل.
5. **الترخيص الحقيقي** بدل المحلي فقط.
6. **ميزات Post-v1** بعد استقرار MVP.

## ملاحظة عن تقرير التدقيق 2026-09-11
`docs/progress-audit-2026-09-11.md` يعكس حالة وسيطة. الحالة الحالية في هذا الملف وفي CI و`product-decisions.md` هي المرجع.
