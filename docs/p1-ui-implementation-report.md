# تقرير P1 — تقارير فرعية وإعدادات وقوالب

**التحقق**

```text
dart analyze lib test  → No issues found! (info فقط غير حاجب)
flutter test           → All tests passed! (45)
flutter build web      → يُذكر أدناه حسب بيئة البناء
```

## ما أُغلق من فجوة Kotlin (وظيفيًا — بيانات حقيقية)

| المسار | الحالة |
|---|---|
| تقارير: مبيعات يوم/شهر | مربوط `sales.listCompletedBetween` |
| سجل العمليات | مربوط `transactions.listRecent` |
| تقرير نقاط البيع | مربوط `pointsOfSale.listAll` (لا ربط بيع↔POS في Domain) |
| رسائل مرفوضة | `messages.listByStatus(rejected)` |
| رسائل معلّقة | received + parsed + failed |
| إعدادات الشريحة | `AppSettings` محلي |
| البطارية | إعداد إقرار محلي |
| قوالب التحويل | `TransferTemplateRepository` + CRUD قائمة |
| تصدير السجل | CSV من المعاملات + نسخ للحافظة |
| تنظيف السجلات | عدّادات + استعادة معلّق عبر recovery (لا حذف جماعي في Domain) |
| تجديد/تفعيل | `licenseService.activateOffline` |
| مركز المساعدة | مواضيع offline ثابتة |
| Wallets/POS | قائمة + إنشاء (من P0، ما زالت مربوطة) |
| Widget smoke tests | Offers, Help, Async views |

## ما بقي صراحةً

- مطابقة بصرية/تدفقية كاملة لـ BottomSheets المعقّدة في Kotlin Dashboard
- تقرير مبيعات POS بمبالغ (يتطلب ربط Sale↔POS غير موجود في Domain الحالي — **لم يُختلق**)
- محاكاة قالب متقدمة كمعالج منفصل
- حذف سجلات جماعي (لا API في Domain)
- Widget tests مع AppContainer كامل لكل شاشة
- Post-v1 مؤجّل

## صياغة دقيقة

الشاشات **مربوطة ببيانات حقيقية مع حالات Loading/Empty/Error أساسية**، وليست «مطابقة مكتملة لـ Kotlin».
