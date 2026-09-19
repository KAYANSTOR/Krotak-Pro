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

1. **بيع مباشر (يدوي)** — إعادة تصميم كاملة على نمط الصورة المرجعية:
   - حقل رقم جوال مع **منتقي جهات اتصال الجهاز** (أيقونة يسار الحقل).
   - **كشف عميل موجود**: عند اكتمال رقم صحيح يظهر شارة «عميل موجود · الاسم»
     (قراءة عرضية عبر `findByIdentifier` فقط — لا تؤثر على مسار البيع)،
     أو «عميل غير معروف — يُنشأ تلقائيًا عند البيع».
   - تأكيد أخضر على صحة الرقم + المبلغ + الاسم + شرائح طريقة البيع الأربع.
2. **إنشاء حساب مشترك جديد** — نموذج الحقول السبعة من الصورة المرجعية:
   جوال GSM، جوال بديل لاستلام الرسائل، الاسم، اسم المرسل ONE CASH/FLOOSAK،
   الرقم البديل واسم المرسل JAIB — كل الحقول الرقمية بمنتقي جهات اتصال.
   يُفتح من شاشة الحسابات (بديل النموذج القديم) ومن الإجراءات السريعة.
3. **منتقي جهات الاتصال** (`lib/platform/contact_picker_bridge.dart` +
   `pickContact` في MainActivity): طلب صلاحية `READ_CONTACTS` تلقائيًا،
   تطبيع الرقم الكانوني عبر `PhoneNormalizer.canonicalize`، وسلوك صامت في
   الاختبارات/غياب المنصة.
4. **نظام المظهر الثلاثي** (بديل فاتح/داكن): نهاري · ليلي · **تلقائي — داكن
   من 7 مساءً إلى 7 صباحًا وفاتح بقية اليوم** مع مؤقّت دقيقة يعيد الحسم
   عند تغيّر الوقت، وتوافق خلفي: `system` القديمة تُقرأ نهاريًا.
   ورقة اختيار بمعاينات مصغّرة مبنية من ألوان الهوية نفسها.
5. **ورقة مخزون الكروت** على نمط الصورة المرجعية: صف لكل فئة
   (نقطة ملونة · الاسم · شارة «منخفض» · عدّاد متوفر/الإجمالي · شريط أفقي)،
   مع قسم الكروت المحجوزة (تدخل يدوي) كما هو، وذيل بالإجمالي والتحذير والانتقال.

الاختبارات: `test/widget/theme_schedule_test.dart`،
`test/platform/contact_picker_bridge_test.dart` (تحليل + تشغيل في CI).

### إغلاق اتساق الهوية البصرية — الجولة الختامية (2026-09-18) ✅ برمجيًا

> UI/Presentation فقط. لم يُعدّل أي ملف من `lib/domain/**` أو `lib/data/**` أو
> `lib/application/**` أو `lib/platform/**`، ولا أي مسار أو معالج حدث أو استدعاء خدمة.

1. **إغلاق آخر الألوان الثابتة:** استُبدلت بقايا `Colors.grey.shade600/300` برموز
   الثيم (`Theme.of(context).colorScheme.onSurfaceVariant` للنص الثانوي،
   `KayanPalette.of(...).border` لمقابض الأوراق) في `failed_messages_screen`،
   `salafni_templates_screen`، `sim_settings_screen`، `templates_screen`،
   `wallets_pos_screen`. النتيجة: صفر `Colors.grey` في `lib/ui`.
2. **إغلاق مصفوفة التغطية:** لم تبقَ أي شاشة على التصميم القديم؛ تمّت مراجعة
   `sales_period_report_screen`، `outbound_message_templates_screen`،
   `sales_period_sheet`، `direct_sale_sheet` وكلها الآن على `KayanPalette` +
   `NetSemanticColors` + `NetSurfaceCard` + `NetSpacing/NetRadii`.
3. **إصلاح بوابة CI:** حُذف المعامل غير المستخدم `hint` في `_CustField`
   (`customer_create_sheet`) وهو التحذير الوحيد الذي كان يُفشل `flutter analyze`،
   مع تنظيف الاستيراد/العضو/التحويل الزائدة.

المرجع: [ui-design-refresh-plan.md](ui-design-refresh-plan.md) §3.1.

4. **إصلاح ثلاثة أخطاء تخطيط حقيقية** ظهرت بعد أن توقّف التحذير عن حجب مجموعة الاختبارات:
   - ورقة اختيار المظهر: صفّ الخيارات الثلاثة كان `stretch` داخل تمرير عمودي بلا
     ارتفاع محدود (‏`BoxConstraints forces an infinite height`) فصار داخل `IntrinsicHeight`.
   - الحالات الفارغة/الخطأ (`AsyncEmptyView` / `AsyncErrorView`): كانت تتمركز بعمود
     ثابت الارتفاع فينزلق المحتوى خارج الشاشة القصيرة؛ صارت داخل غلاف
     `_ScrollableCenter` يتمركز عند توفر المساحة ويمرّر عند ضيقها — إصلاح يسري على كل
     الشاشات التي تستخدم الحالتين.
   - ورقة الإجراءات السريعة: ستة إجراءات في عمود ثابت تجاوزت ارتفاع الورقة النمطية
     بمقدار 180 بكسل؛ صارت `isScrollControlled` + قائمة قابلة للتمرير.

   كذلك أُغلقت بقايا ألوان `Colors.grey` في خمس شاشات، فلم يبقَ أي لون ثابت للنص أو
   الأسطح أو الفواصل في `lib/ui`.

**تحقق CI:** [run 35325003617](https://github.com/KAYANSTOR/net-flutter/actions/runs/35325003617)
— `flutter analyze` نظيف · **كل الاختبارات نجحت (203)** · بناء APK للإصدار ونجح
نشر GitHub Release.

**بانتظار جهاز حقيقي:** التدقيق البصري النهائي (فاتح + داكن) وحزمة أدلة لقطات
الشاشات — لا تُخترع نتائج جهاز.
