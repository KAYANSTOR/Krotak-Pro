# تقدم تنفيذ خطة NET

## التحقق (2026-09-12)

```text
CI على main (آخر تشغيل): success
dart analyze lib test  → يمر في CI
flutter test           → يمر في CI
```

تم إغلاق فجوة العقود والاختبارات التي وردت في تقرير 11 سبتمبر بعد سلسلة hardening للتدفق الأساسي.

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

### CI
- `.github/workflows/ci.yml` يشغّل analyze + test على كل push/PR — أخضر على main

## متبقٍ (بالترتيب الجذري)

1. **عينات قوالب SMS حقيقية** من المحافظ المعتمدة (قرار من صاحب المشروع) ثم تثبيت القوالب الافتراضية.
2. **اختبار جهاز حقيقي** لمسار SMS الكامل (استقبال → معالجة → إرسال → استعادة بعد إعادة التشغيل).
3. **الترخيص الحقيقي** (Backend / مفتاح / offline grace) بدل المحلي فقط.
4. **مطابقة بصرية أدق** لـ BottomSheets المعقّدة في Kotlin إن لزم.
5. **ميزات Post-v1** (سلفني، إشعارات محافظ، تسوية POS تلقائية، بث جماعي) — بعد استقرار MVP.

## ملاحظة عن تقرير التدقيق 2026-09-11
`docs/progress-audit-2026-09-11.md` يعكس حالة وسيطة قبل hardening التدفق الأساسي وإصلاح العقود. الحالة الحالية في هذا الملف وفي CI هي المرجع.
