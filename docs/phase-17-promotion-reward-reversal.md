# Phase 17 — عكس مكافأة العرض عند reverseSale

**تاريخ:** 2026-09-16  
**الحالة:** منفذة في المستودع  
**الأساس:** بند خارج نطاق Phase 15 وPhase 16: «عكس المكافأة عند `reverseSale`».

## النطاق

- احتساب تقدم العرض يخصم حركات `reversal` المرتبطة بمبيعات (`TransactionType.sale`) فقط.
- بعد نجاح `reverseSale` يُستدعى `reclaimUnqualified`.
- الدورات التي لم تعد مستحقة تُعكس: إعادة الكرت إلى `available`، بيع المكافأة `reversed`، حركة `reversal` بمرجع `reversal:promo-sale:{promo}:{customer}:{cycle}`، وتدقيق `reward_reclaimed`.
- معرف بيع المكافأة أصبح مستقراً: `promo-sale:{promoId}:{customerId}:{cycle}`.
- ربط `LocalPromotionFulfillmentService` في `AppContainer` و`LocalSaleService` بعد اكتمال البيع (Phase 15 كانت موثّقة دون تركيب كامل).

## خارج النطاق

- بوابات Phase 12 على جهاز حقيقي.
- قياس أداء الاستيراد والبث على جهاز.

## معيار القبول

1. بيع يبلغ العتبة يصرف مكافأة.
2. عكس ذلك البيع يسحب المكافأة ويعيد الكرت للمخزون.
3. إعادة الاستدعاء لا تكرر العكس.
4. عكس المكافأة لا يغيّر نتيجة `reverseSale` الأصلية إن فشل الاسترداد لاحقاً داخل خدمة الصرف فقط بعد نجاح العكس.
