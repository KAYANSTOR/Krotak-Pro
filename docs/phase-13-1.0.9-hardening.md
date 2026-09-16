# Phase 13 — 1.0.9 Hardening (Reserved Cards + Promotions)

**تاريخ:** 2026-09-16  
**الحالة:** منفذة في المستودع (اختبارات + توثيق)  
**الأساس:** ميزات `feat(1.0.9)` التي دخلت `main` بعد إغلاق البنود البرمجية الرسمية لـ Post-V1.

## لماذا هذه المرحلة

`docs/progress.md` أغلق Post-V1 عند Phase 12: لا بنود برمجية رسمية متبقية سوى تشغيل بوابات التحقق على جهاز Android حقيقي.

بعد ذلك دخلت إلى `main` قدرات 1.0.9 دون مرحلة توثيق/اختبار مستقلة:

- تأكيد تسليم يدوي للكرت المحجوز / تحرير الحجز مع Rollback.
- تقدم العميل نحو عروض تراكمية (`LocalPromotionProgressService`).
- وضع عمولة نقطة البيع وطرق البيع هدية/POS في الواجهة.

Phase 13 لا تخترع منتجاً جديداً؛ تثبّت العقود الموجودة باختبارات Domain وتوثّقها كمرحلة رسمية.

## النطاق

- `LocalVoucherOpsService.confirmManualDelivery`
- `LocalVoucherOpsService.releaseReservationAndRollback`
- `LocalPromotionCatalog` + `LocalPromotionProgressService.forCustomer`
- اختبارات: `test/services/voucher_ops_and_promotion_progress_test.dart`

## خارج النطاق

- تشغيل بوابات Phase 12 على جهاز حقيقي (ما زال مطلوباً قبل Production Ready).
- صرف مكافأة العرض تلقائياً عند بلوغ العتبة (التقدم يُحسب فقط؛ الصرف قرار منتج لاحق).
- عينات إشعارات محافظ حقيقية.

## معيار القبول

1. تأكيد التسليم اليدوي يحوّل الكرت المحجوز إلى `sold` ويسجّل Audit.
2. تأكيد التسليم على كرت `available` يُرفض بـ `card_not_reserved`.
3. تحرير الحجز يعيد الكرت إلى `available`.
4. تقدم العرض يراكم حركات `sale` المكتملة بنفس العملة فقط.
5. بلوغ العتبة يجعل `qualified == true`.

## المتبقي التشغيلي

بوابات Phase 12 على Android حقيقي + قياس استيراد الدفعات وبث SMS على الجهاز.
