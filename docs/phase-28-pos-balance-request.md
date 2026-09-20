# مرحلة 28 — طلب رصيد نقطة البيع

**التاريخ:** 2026-09-20  
**الأصل:** البند 1 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

تفعيل القالب الخامس المزروع لكل نقطة بيع («قالب طلب رصيد نقطة البيع») بمسار مستقل عن `MessageParser`، لأن الرمز لا يحمل مبلغاً.

## التدفق

```text
SMS وارد
  → تطبيع جسم الرسالة إلى رمز
  → التعرف على نقطة البيع من رقم المرسل
  → مطابقة الرمز المحفوظ (الافتراضي 111، أرقام عربية مقبولة)
  → فحص الإعداد pos_balance_requests_enabled
  → فحص الحد اليومي
  → قراءة رصيد دفتر نقطة البيع
  → إرسال قالب الرد أو قالب الرفض
  → تدقيق + زيادة العدّاد اليومي
```

## المنفَّذ

| بند | أين |
|---|---|
| `LocalPosBalanceQueryService` | `lib/domain/services/local_pos_balance_query_service.dart` |
| حقول `balanceRequestCode` و`dailyBalanceRequestLimit` | `PosAccount` |
| ربط الاستقبال قبل محرك التحويل | `IncomingSmsHandler` |
| حقول النموذج | `wallets_pos_screen.dart` |
| عدّاد يومي | `SettingKeys.posBalanceRequestCounts` |
| اختبارات | `test/services/pos_balance_query_service_test.dart` |
