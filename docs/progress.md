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
- ثيم Kayan + RTL + Bottom Navigation

### Dashboard — كرت الرصيد / Header / Alert / Metric Cards / بيع يدوي
- معتمدة PD-01…04 و PD-06 — انظر [product-decisions.md](product-decisions.md)

### مركز المساعدة — B8 منفَّذ (2026-09-12)
- `HelpCenterScreen` موسّع من PD-07 Q8 + business-rules + السلوك المنفَّذ فقط
- مواضيع: مفهوم النظام · دورة SMS · إعدادات · معلّقة · مرفوضة · عملاء · دفتر · بيع يدوي · فئات/مخزون · استيراد · حجز FIFO · لوحة التحكم · POS/تسوية · تدقيق/ترخيص
- لا وعود بميزات غير منفَّذة (PDF ثنائي، ترخيص سحابي، جدولة ملخص…)

### الدفعة B — مغلقة (2026-09-12)
معايير الخطة: غير المطابق→معلّقة · اعتماد→إيداع · رفض→مرفوضة · دفتر حقيقي · كروت من مخزون · لا كرت بلا فئة نشطة · استيراد بنص/CSV · فئات مربوطة · مساعدة من PD

### الفئات والكروت والاستيراد — B5–B7 منفَّذ (2026-09-12)
- `InventoryScreen`: بحث فئات · بطاقة فئة · فئة جديدة · عرض كروت · استيراد فردي/جماعي
- `CardImportParser` + اختبارات
- منع الاستيراد لفئة غير نشطة · `CardStockSheet` بأرقام حقيقية

### الحسابات والدفتر — B4 منفَّذ (2026-09-12)
- بطاقات حساب (رصيد متاح / مدين / متوازن) + دفتر CREDIT/DEBIT/REVERSAL

### الرسائل المرفوضة — B3 منفَّذ (2026-09-12)
- `RejectedMessageCatalog` + `RejectedMessagesScreen`

### الرسائل المعلّقة — B2 منفَّذ (2026-09-12)
- `PendingMessageReviewService` + `PendingMessagesScreen`

### إعدادات — B1 / S3 Domain منفَّذ (2026-09-12)
- بوابات PD-07 الثلاثة في handler/processor/recovery + اختبارات

### إعدادات — S1/S2 منفَّذ (2026-09-12)
- أقسام PD-07 + كروت + مفاتيح محلية + اسم الشبكة + المظهر

### CI
- `.github/workflows/ci.yml` — analyze + test على كل push/PR

## متبقٍ (خارج الدفعة B — دفعة لاحقة عند الطلب)

1. **محافظ / POS متقدم / معالج فوسك / محاكاة قوالب / قوالب رسائل العملاء** — خارج نطاق الدفعة B حسب الخطة.
2. **عينات قوالب SMS حقيقية** من المحافظ المعتمدة.
3. **اختبار جهاز حقيقي** لمسار SMS الكامل.
4. **الترخيص الحقيقي** بدل المحلي فقط.
5. **ميزات Post-v1** بعد استقرار MVP.
6. **منهجية مطابقة الواجهة (PD-05)** — مستمر عند وصول ملفات وصف لباقي الشاشات.

## ملاحظة عن تقرير التدقيق 2026-09-11
`docs/progress-audit-2026-09-11.md` يعكس حالة وسيطة. الحالة الحالية في هذا الملف وفي CI و`product-decisions.md` هي المرجع.
