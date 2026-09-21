# ربط بوابة القوالب الصادرة

أي قالب في `outbound_templates_disabled` لا يُرسل.

## المسارات المربوطة

| المسار | مفتاح القالب |
|--------|----------------|
| تسليم كرت (تحويل / عامل التسليم / بيع يدوي) | `voucher_delivery_sms_template` |
| طلب POS → عميل / نقطة بيع | `pos_customer_card_delivery_template` / `pos_order_success_template` |
| رد رصيد نقطة بيع | `pos_balance_response_template` |
| سلفني قبول/رفض/تسديد | مفاتيح سلفني |
| مكافأة عرض | `promotion_reward_sms_template` |
| ملخص يومي POS | `daily_pos_summary_template` |
| تسوية نجاح/فشل | مفاتيح التسوية |
| تنبيه مخزون | `low_stock_alert_template` |

عند الإيقاف: لا SMS + audit `sms_skipped_template_disabled` حيث ينطبق.
