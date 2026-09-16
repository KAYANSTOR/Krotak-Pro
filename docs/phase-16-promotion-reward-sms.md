# Phase 16 — قالب وإرسال SMS لمكافأة العرض

**تاريخ:** 2026-09-16  
**الحالة:** منفذة في المستودع  
**الأساس:** المتبقي التشغيلي بعد Phase 15: «قالب SMS للمكافأة إن اعتُمد».

## النطاق

- قالب قابل للتخصيص في `SettingKeys.promotionRewardSmsTemplate`.
- بعد صرف كرت المكافأة يُرسل SMS إلى رقم العميل الأساسي.
- فشل الإرسال أو غياب الرقم لا يلغي الصرف المكتمل؛ يُسجل Audit (`reward_sms_sent` / `reward_sms_failed` / `reward_sms_skipped`).
- ربط `LocalSaleService` بـ `LocalPromotionFulfillmentService` بعد البيع من الرصيد والبيع اليدوي وإكمال الحجز.

## المتغيرات

`{title}` `{serial}` `{secret}` `{code}` `{amount}`

## خارج النطاق

- بوابات Phase 12 على جهاز حقيقي.
- عكس المكافأة عند `reverseSale`.
