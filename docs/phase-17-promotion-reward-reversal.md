# Phase 17 — عكس مكافأة العرض عند reverseSale

**تاريخ:** 2026-09-16  
**الحالة:** منفذة في المستودع  
**الأساس:** خارج نطاق Phase 15 وPhase 16: «عكس المكافأة عند `reverseSale`».

## النطاق

- حساب تقدّم العرض يخصم حركات `reversal` ذات المرجع `reversal:{saleId}` حتى لا يبقى البيع المعكوس في التراكم.
- `LocalPromotionFulfillmentService.revokeExcessRewards` يعكس دورات المكافأة الزائدة عن الدورات المؤهلة بعد انخفاض التراكم.
- استعادة كرت المكافأة إلى المخزون، حركة دفتر `promo-reward-reversal:{promoId}:{customerId}:{cycle}`، و`Audit` باسم `reward_reversed`.
- `LocalSaleService.reverseSale` يستدعي العكس داخل نفس وحدة العمل.
- ربط الصرف التلقائي بعد اكتمال البيع (استكمال Phase 15 في التركيب الجذري).

## خارج النطاق

- بوابات Phase 12 على جهاز Android حقيقي.
- قياس أداء الاستيراد والبث على جهاز.
