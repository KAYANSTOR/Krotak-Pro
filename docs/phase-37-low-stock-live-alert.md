# مرحلة 37 — إشعار حي بنفاد المخزون ورسالة عميل واضحة

**التاريخ:** 2026-09-20  
**الأصل:** البند 9 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

عندما تنفد كروت فئة مطابقة:

1. يظهر تنبيه حي في لوحة التحكم ولا يمكن إغلاقه يدوياً.
2. يختفي التنبيه فقط بعد إضافة كروت ترفع المتاح فوق عتبة التنبيه.
3. يتلقى العميل (أو رقم التسليم) رسالة SMS واضحة بدل الرفض الصامت.

## السلوك

- خدمة `LocalLowStockAlertService` تعيد بناء قائمة الفئات المنخفضة/النافدة من المخزون الحي.
- الحالة تُحفظ في `SettingKeys.lowStockActiveJson` حتى تبقى بعد إعادة فتح التطبيق.
- عتبة التنبيه تبقى `SettingKeys.lowStockThreshold` (الافتراضي 10).
- عند `out_of_stock` في `LocalTransferProcessor` (طلب فردي أو دفعة):
  - تُعلَّم الفئة نافدة.
  - تُرسل رسالة من قالب `SettingKeys.lowStockAlertTemplate`.
  - يُسجَّل Audit `out_of_stock_customer_sms_sent` أو `out_of_stock_customer_sms_skipped`.
- شريط لوحة التحكم لم يعد يقبل `onDismiss` لتنبيه المخزون.

## القالب الافتراضي

```
عذراً، كروت فئة {category} غير متوفرة حالياً (المتبقي: {count}). يرجى التواصل مع الإدارة.
```
