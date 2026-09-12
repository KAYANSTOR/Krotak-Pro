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

### Dashboard — كرت الرصيد (معتمد 2026-09-12)
- عنوان العرض: **إجمالي رصيد العملاء (المعلق)** = دين العملاء من ledger عبر `getTotalOutstanding(YER)`
- الحسابات → تبويب `accounts`
- كروت متوفرة → `CardStockSheet` (فئات + متاح/إجمالي + شارة منخفض عند 0) من Repositories الحقيقية ثم زر إلى تبويب `cards`
- جسم الكرت بلا إجراء
- المرجع التفصيلي: [product-decisions.md](product-decisions.md) PD-2026-09-12-01

### Dashboard — Header (معتمد 2026-09-12)
- شعار + **اسم الشبكة** من `SettingKeys.networkName` (افتراضي `NET`) قابل للتعديل من الإعدادات
- تاريخ واسم اليوم عبر `Clock` + تنسيق عربي
- أيقونة إعدادات → `AppRoutes.openSettings` (وإعادة تحميل الاسم بعد العودة)
- أيقونة مساعدة → `AppRoutes.openHelp` → `HelpCenterScreen`
- **لا** ترخيص ولا SMS داخل الـ Header
- المرجع: [product-decisions.md](product-decisions.md) PD-2026-09-12-02

### Dashboard — Alert Banner (معتمد 2026-09-12)
- يعرض **عدد الرسائل المرفوضة أو المعلّقة** فقط (يختفي عند 0)
- مرفوضة = `rejected` · معلّقة = `received` + `parsed` + `failed` من `MessageRepository`
- الضغط → `AppRoutes.openAttentionMessages` → شاشة القائمة ثم إعادة تحميل العدد
- **لا** SMS / ترخيص / خطأ تحميل عام في هذا الـ Banner
- المرجع: [product-decisions.md](product-decisions.md) PD-2026-09-12-03

### Dashboard — Metric Cards مبيعات اليوم/الشهر (معتمد 2026-09-12)
- مبيعات اليوم والشهر من `SaleRepository.listCompletedBetween` فقط (مكتملة)
- الضغط → `SalesPeriodSheet` مطابق للقطة Kotlin: عنوان «تفاصيل مبيعات…»، فراغ «لا توجد مبيعات مسجلة لهذه الفترة»، إجمالي المبيعات `ر.ي (N كرت)`، زر «الذهاب إلى تقرير المبيعات التفصيلي»
- إجمالي الرصيد المعلق يبقى دين العملاء من الـ ledger (`getTotalOutstanding`)
- المرجع: [product-decisions.md](product-decisions.md) PD-2026-09-12-04

### CI
- `.github/workflows/ci.yml` يشغّل analyze + test على كل push/PR — أخضر على main

## متبقٍ (بالترتيب الجذري)

1. **منهجية مطابقة الواجهة لكل النظام (PD-05)** — التالي فورًا: حوار **بيع مباشر - يدوي** حسب اللقطة المرجعية، ثم باقي الشاشات عنصرًا بعنصر.
2. **عينات قوالب SMS حقيقية** من المحافظ المعتمدة (قرار من صاحب المشروع) ثم تثبيت القوالب الافتراضية.
3. **اختبار جهاز حقيقي** لمسار SMS الكامل (استقبال → معالجة → إرسال → استعادة بعد إعادة التشغيل).
4. **الترخيص الحقيقي** (Backend / مفتاح / offline grace) بدل المحلي فقط.
5. **ميزات Post-v1** (سلفني، إشعارات محافظ، تسوية POS تلقائية، بث جماعي) — بعد استقرار MVP.

## ملاحظة عن تقرير التدقيق 2026-09-11
`docs/progress-audit-2026-09-11.md` يعكس حالة وسيطة قبل hardening التدفق الأساسي وإصلاح العقود. الحالة الحالية في هذا الملف وفي CI و`product-decisions.md` هي المرجع.
