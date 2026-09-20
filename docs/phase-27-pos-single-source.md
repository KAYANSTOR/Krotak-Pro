# مرحلة 27 — مصدر واحد لملف نقطة البيع

**التاريخ:** 2026-09-20  
**الأصل:** البند 0 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

إعادة تطبيق فكرة `refactor/pos-single-source` بشكل صحيح دون كسر الاستيرادات أو قطع شاشة الدفتر:

خدمة واحدة تنفّذ التحقق ثم الإنشاء/التعديل وزرع القوالب الخمسة.

## المنفَّذ

| بند | أين |
|---|---|
| `LocalPosProfileService` + `PosProfile` | `lib/domain/services/local_pos_profile_service.dart` |
| التحقق: اسم مكرر · رقم مرتبط بنقطة أخرى · رقم عميل قائم | `validate` |
| إنشاء: عميل دفتر + كتالوج + `PosAccount` + زرع القوالب | `create` |
| تعديل: كتالوج + ربط الحساب | `update` |
| ربط الحاوية | `AppContainer.posProfile` |
| شاشة المحافظ / نقاط البيع | `wallets_pos_screen.dart` |
| نموذج الدفتر | `pos_accounts_ledger_screen.dart` |
| اختبارات | `test/services/pos_profile_service_test.dart` |

لم يُنقل `PointOfSale` خارج `wallet.dart`، ولم تُستبدل شاشة الدفتر — ذلك كان سبب كسر الدمج السابق.

## غير المشمول (يبقى في قائمة المرحلة 26)

طلبات الرصيد، عدة كروت دفعة واحدة، الشحن الفوري، تسعير الجملة بعد النسبة، التسوية التلقائية، الأرقام المحظورة، …
