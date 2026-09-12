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

### الفئات والكروت والاستيراد — B5–B7 منفَّذ (2026-09-12)
- `InventoryScreen`: بحث فئات · بطاقة فئة (متاح/محجوز/مباع + منخفض) · فئة جديدة · عرض كروت · استيراد فردي/جماعي
- `CardImportParser`: CSV/فاصلة/فاصلة منقوطة/تاب + تخطي التعليقات والرأس + كشف التكرار
- منع الاستيراد لفئة غير نشطة
- `CardStockSheet` (موجود) يعرض أرقامًا حقيقية من المخزون
- اختبارات: `test/services/card_import_parser_test.dart`

### الحسابات والدفتر — B4 منفَّذ (2026-09-12)
- `CustomersScreen`: بحث · بطاقة حساب (رصيد متاح / مدين / متوازن) · إضافة عميل
- `CustomerDetailScreen`: رأس هوية · بطاقة رصيد مدين/دائن · دفتر حركات حقيقي (إيداع/بيع/سحب/تسوية/عكس) مع وسم CREDIT/DEBIT/REVERSAL
- الاعتماد من المعلّقة يظهر كـ `deposit` في نفس الحساب

### الرسائل المرفوضة — B3 منفَّذ (2026-09-12)
- `RejectedMessageCatalog` + `RejectedMessagesScreen` (فلاتر/إجمالي/جديد/بطاقات)

### الرسائل المعلّقة — B2 منفَّذ (2026-09-12)
- `PendingMessageReviewService` + `PendingMessagesScreen`

### إعدادات — B1 / S3 Domain منفَّذ (2026-09-12)
- بوابات PD-07 الثلاثة في handler/processor/recovery + اختبارات

### إعدادات — S1/S2 منفَّذ (2026-09-12)
- أقسام PD-07 + كروت + مفاتيح محلية + اسم الشبكة + المظهر

### CI
- `.github/workflows/ci.yml` — analyze + test على كل push/PR

## متبقٍ (بالترتيب الجذري)

1. **الدفعة B** — S0–S2✓ · B1✓ · B2✓ · B3✓ · B4✓ · **B5–B7 ✓**. التالي: **B8 مساعدة**.
2. **منهجية مطابقة الواجهة (PD-05)** — مستمر لباقي الشاشات (محافظ، فوسك، محاكاة، قوالب عملاء = دفعة لاحقة).
3. **عينات قوالب SMS حقيقية** من المحافظ المعتمدة.
4. **اختبار جهاز حقيقي** لمسار SMS الكامل.
5. **الترخيص الحقيقي** بدل المحلي فقط.
6. **ميزات Post-v1** بعد استقرار MVP.

## ملاحظة عن تقرير التدقيق 2026-09-11
`docs/progress-audit-2026-09-11.md` يعكس حالة وسيطة. الحالة الحالية في هذا الملف وفي CI و`product-decisions.md` هي المرجع.
