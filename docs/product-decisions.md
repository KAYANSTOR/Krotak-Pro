# قرارات المنتج المعتمدة (Product Decisions)

**الحالة:** مصدر حقيقة أعلى من Kotlin ومن أي افتراض سابق للوكيل.

**القاعدة:**

1. كل قرار تجاري أو سلوك واجهة يؤكده صاحب المشروع يُسجَّل هنا قبل أو مع التنفيذ.
2. عند التعارض: **هذا الملف > progress.md > Kotlin UI > تخمين الوكيل**.
3. Kotlin = مرجع بصري/تاريخي فقط، وليس Business Truth تلقائيًا.
4. لا يُنفَّذ سلوك مخالف لما هنا دون تحديث هذا الملف أولًا.

---

## PD-2026-09-12-01 — كرت الرصيد في Dashboard

| الحقل | القيمة المعتمدة |
|--------|------------------|
| **Screen** | Dashboard |
| **Element** | Balance Card / إجمالي رصيد العملاء (المعلق) |
| **Status** | Confirmed by product owner |
| **Date** | 2026-09-12 |

### المعنى

- **إجمالي رصيد العملاء (المعلق)** = **الدين / أرصدة جميع حسابات العملاء** المستمدة من دفتر الحركات (ledger).
- **ليس** رصيد الشبكة / المشغّل.
- **ليس** تجميعًا منفصلًا لحالة `TransactionStatus` مختلفة عن منطق الرصيد المعتمد.

### مصدر الحقيقة (Source of Truth)

```text
CustomerBalanceService.getTotalOutstanding(currencyCode: 'YER')
  → TransactionRepository.listCompleted(currencyCode)
  → sumCompletedLedger (نفس قواعد business-rules.md للأرصدة)
```

- العملة المعروضة في Dashboard حاليًا: **YER فقط**.
- المعمارية تبقى قابلة لتعدد العملات لاحقًا عبر `currencyCode` (لا يُصلَّب مسار يمنع الإضافة).

### تفاعلات الضغط

| المنطقة | السلوك المعتمد |
|---------|----------------|
| جسم الكرت | **لا إجراء** |
| شريحة **الحسابات** | الانتقال إلى تبويب Bottom Nav: `accounts` (شاشة الحسابات) |
| شريحة **كروت متوفرة** | فتح **Bottom Sheet** «مخزون الكروت حسب الفئة» |

### محتوى Bottom Sheet (كروت متوفرة)

- العنوان: **مخزون الكروت حسب الفئة**
- لكل فئة نشطة من `CardCategoryRepository.listAll`:
  - اسم الفئة (أو «كرت {قيمة اسمية}» إن لزم)
  - العدد: `متاح / إجمالي` حيث الإجمالي = available + reserved + sold لنفس الفئة
  - شارة **منخفض** عندما `available == 0`
- ملخص: «X متوفر من Y»
- زر: **الذهاب إلى إدارة الكروت** → تبويب `cards` (Inventory)
- **البيانات من المستودعات الحقيقية فقط** — ممنوع Mock / Fake / أرقام ثابتة في المنتج.

### التنفيذ في المستودع

| ملف | دور |
|-----|-----|
| `lib/ui/widgets/net/net_balance_card.dart` | عرض العنوان والأرقام والشرائح |
| `lib/ui/widgets/dashboard/card_stock_sheet.dart` | الـ Sheet + تحميل المخزون |
| `lib/ui/screens/dashboard_screen.dart` | ربط المصدر والتفاعلات |
| `lib/domain/services/local_customer_balance_service.dart` | `getTotalOutstanding` |

### ما يُلغى من الافتراضات السابقة

- اعتبار شريحة الكروت تنتقل مباشرة لتبويب الكروت **فقط** دون Sheet → **ملغى**.
- نسخ بيانات Kotlin الثابتة للرصيد أو المخزون → **مرفوض**.

---

## PD-2026-09-12-02 — Header لوحة التحكم (Dashboard Header)

| الحقل | القيمة المعتمدة |
|--------|------------------|
| **Screen** | Dashboard |
| **Element** | NetDashboardHeader |
| **Status** | Confirmed by product owner |
| **Date** | 2026-09-12 |

### المعنى / المحتوى المعتمد

الـ Header يعرض **فقط**:

1. **شعار البرنامج** + **اسم الشبكة** (اسم البرنامج القابل للتعديل).
2. **تاريخ واسم اليوم** (من ساعة الجهاز عبر `Clock`).
3. **أيقونة الإعدادات** → شاشة الإعدادات.
4. **أيقونة المساعدة** → شاشة مركز المساعدة.

**لا يُعرض في الـ Header:** حالة الترخيص، حالة SMS، رسائل متبقية، بطاقة حالة نظام، أو أي سطر فرعي تشغيلي آخر.

### اسم الشبكة — مصدر الحقيقة

```text
SettingsRepository.find(SettingKeys.networkName)
  → القيمة المحفوظة إن وُجدت وغير فارغة بعد trim
  → وإلا الافتراضي: "NET"
```

- المفتاح: `SettingKeys.networkName` = `network_name`
- التعديل: من **الإعدادات → اسم الشبكة** (حفظ عبر `SettingsRepository.save`)
- بعد الحفظ والعودة للوحة: يُعاد تحميل الاسم في الـ Header

### التاريخ

- المصدر: `Clock.now()` (لا نص ثابت)
- العرض: اسم اليوم + رقم اليوم + اسم الشهر بالعربية (مثال: `السبت، 12 سبتمبر`)
- بلا ضغط

### تفاعلات الضغط

| المنطقة | السلوك المعتمد |
|---------|----------------|
| الشعار / اسم الشبكة / التاريخ | **لا إجراء** |
| أيقونة الإعدادات | `AppRoutes.openSettings` |
| أيقونة المساعدة | `AppRoutes.openHelp` → `HelpCenterScreen` |

### التنفيذ في المستودع

| ملف | دور |
|-----|-----|
| `lib/domain/entities/setting.dart` | مفتاح `networkName` + ثابت الافتراضي |
| `lib/ui/widgets/net/net_app_logo.dart` | شعار البرنامج |
| `lib/ui/widgets/net/net_dashboard_header.dart` | التخطيط والتفاعلات |
| `lib/ui/screens/dashboard_screen.dart` | تحميل الاسم والتاريخ |
| `lib/ui/routing/app_routes.dart` | `openHelp` |
| `lib/ui/screens/settings/network_name_settings_screen.dart` | تعديل وحفظ اسم الشبكة |
| `lib/ui/screens/settings/settings_hub_screen.dart` | دخول «اسم الشبكة» |

### ما يُلغى

- عرض الترخيص أو SMS داخل الـ Header → **ملغى**.
- عنوان ثابت غير قابل للتعديل دون مسار إعدادات → **ملغى**.
- زر بحث في Header Dashboard → **غير مستخدم / غير مطلوب**.
- قيم Kotlin الوهمية (اشتراك/رسائل متبقية في الـ Header) → **مرفوض**.

---

## PD-2026-09-12-03 — Alert Banner في Dashboard

| الحقل | القيمة المعتمدة |
|--------|------------------|
| **Screen** | Dashboard |
| **Element** | NetAlertBanner |
| **Status** | Confirmed by product owner |
| **Date** | 2026-09-12 |

### المعنى

الـ Banner يعرض **عدد الرسائل المرفوضة أو المعلّقة** فقط، ويختفي عندما يكون العدد صفرًا.

### تصنيف الحالات (مطابق لتقارير التطبيق)

| التصنيف | `MessageProcessingStatus` |
|---------|---------------------------|
| **مرفوضة** | `rejected` |
| **معلّقة** | `received` + `parsed` + `failed` |

```text
count = len(listByStatus(rejected))
      + len(listByStatus(received))
      + len(listByStatus(parsed))
      + len(listByStatus(failed))
```

- المصدر: `MessageRepository.listByStatus` فقط — ممنوع أرقام ثابتة.
- `processed` لا يدخل في العدد.

### الظهور والنص

- يظهر فقط إذا `count > 0`
- النص المعتمد: **«لديك {N} رسالة مرفوضة أو معلّقة»** (مع مراعاة صيغة المفرد عند N = 1 إن رُغبت لاحقًا؛ الحالي بصيغة موحّدة واضحة)
- لا يعرض تحذير SMS أو الترخيص أو أخطاء التحميل العامة في هذا الـ Banner

### تفاعل الضغط

| المنطقة | السلوك |
|---------|--------|
| الـ Banner | فتح شاشة **الرسائل المرفوضة والمعلّقة** |

الشاشة = `MessagesByStatusScreen` بالحالات الأربع أعلاه، العنوان: **الرسائل المرفوضة والمعلّقة**.  
المسار: `AppRoutes.openAttentionMessages`.

بعد العودة من الشاشة: يُفضَّل إعادة تحميل العدد في اللوحة.

### ما يُلغى

- استخدام الـ Banner لترخيص / إذن SMS / خطأ تحميل عام → **ملغى** لهذا العنصر.
- أي عدد وهمي أو Mock → **مرفوض**.

### التنفيذ

| ملف | دور |
|-----|-----|
| `lib/ui/screens/dashboard_screen.dart` | عدّ الحالات وربط الـ Banner |
| `lib/ui/widgets/net/net_alert_banner.dart` | العرض |
| `lib/ui/routing/app_routes.dart` | `openAttentionMessages` |
| `lib/ui/screens/reports/messages_by_status_screen.dart` | قائمة الرسائل |

---

## PD-2026-09-12-04 — Metric Cards: مبيعات اليوم / مبيعات الشهر

| الحقل | القيمة المعتمدة |
|--------|------------------|
| **Screen** | Dashboard |
| **Element** | NetMetricCard — مبيعات اليوم، مبيعات الشهر |
| **Status** | Confirmed by product owner |
| **Date** | 2026-09-12 |

### المعنى

- **مبيعات اليوم** = مجموع مبالغ عمليات البيع **المكتملة** من بداية اليوم المحلي حتى الآن.
- **مبيعات الشهر** = مجموع مبالغ عمليات البيع **المكتملة** من أول يوم في الشهر المحلي حتى الآن.
- المصدر الوحيد: `SaleRepository.listCompletedBetween(from, now)` — حالات `completed` فقط (كما يصفّي المستودع).
- **كل الأرقام حقيقية من النظام** — ممنوع Mock أو قيم ثابتة في المنتج.

### مصدر الحقيقة (Source of Truth)

```text
dayStart = DateTime(year, month, day)
monthStart = DateTime(year, month, 1)
now = Clock.now()

SaleRepository.listCompletedBetween(dayStart|monthStart, now)
  → sum(amount.minorUnits), count = length
```

- العملة المعروضة في الملخص حاليًا عبر `formatMoneyMinor` (YER / ر.ي).
- إجمالي الرصيد المعلق في Balance Card يبقى دين العملاء من الـ ledger (`getTotalOutstanding`) — غير مرتبط بمجموع المبيعات.

### تفاعلات الضغط

| المنطقة | السلوك المعتمد |
|---------|----------------|
| بطاقة **مبيعات اليوم** | فتح **Bottom Sheet** بنصف شاشة تقريبًا (نفس فكرة كروت المتوفرة) |
| بطاقة **مبيعات الشهر** | فتح **Bottom Sheet** بنصف شاشة بنفس النمط للفترة الشهرية |
| جسم البطاقة بدون Sheet | غير مستخدم — الضغط يفتح الـ Sheet فقط |

### محتوى Bottom Sheet (مبيعات الفترة)

- العنوان: **مبيعات اليوم** أو **مبيعات الشهر**
- قائمة عمليات البيع المكتملة في الفترة (الأحدث أولًا):
  - اسم العميل (من `CustomerRepository.findById`؛ إن تعذّر → `customerId`)
  - الوقت (ليوم) أو التاريخ+الوقت (للشهر)
  - مبلغ العملية
- عند الفراغ: رسالة صادقة («لا توجد مبيعات مكتملة اليوم/هذا الشهر»)
- ملخص سفلي: **إجمالي اليوم/الشهر** + عدد العمليات
- زر: **الذهاب إلى سجل العمليات** → `AppRoutes.openTransactionsLog`
- **البيانات من المستودعات الحقيقية فقط**

### التنفيذ في المستودع

| ملف | دور |
|-----|-----|
| `lib/ui/widgets/dashboard/sales_period_sheet.dart` | الـ Sheet + تحميل المبيعات وأسماء العملاء |
| `lib/ui/screens/dashboard_screen.dart` | ربط Metric Cards + فتح اليوم/الشهر |
| `SaleRepository.listCompletedBetween` | مصدر القائمة والمجاميع |

### ما يُلغى

- الانتقال المباشر من بطاقة المبيعات إلى سجل العمليات **بدون** Sheet تفصيلي → **ملغى** لهذا العنصر (الزر داخل الـ Sheet يبقى للسجل).
- أي أرقام وهمية للمبيعات على اللوحة → **مرفوض**.

---

## قالب إضافة قرار لاحق

```markdown
## PD-YYYY-MM-DD-NN — عنوان مختصر

| الحقل | القيمة |
|--------|--------|
| Screen / Element | |
| Status | Confirmed by product owner |
| Date | |

### المعنى / القاعدة
...

### مصدر الحقيقة
...

### تفاعلات الواجهة
...

### التنفيذ
...
```
