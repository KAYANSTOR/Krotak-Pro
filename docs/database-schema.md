# مخطط قاعدة البيانات المحلية (Drift)

## الجداول الرئيسية

- `customers` — العملاء
- `wallets` — المحافظ والأرصدة
- `card_categories` — فئات الكروت
- `cards` — المخزون الفردي للكروت
- `messages` — رسائل SMS الواردة
- `transactions` — المعاملات المالية
- `audit_logs` — سجل التدقيق
- `settings` — إعدادات التطبيق
- `licenses` — حالة الترخيص

## قيود uniqueness المهمة

- رقم الهاتف للعميل فريد عند التفعيل.
- رقم الكارت / serial فريد داخل الفئة أو عالمياً حسب القاعدة المعتمدة.
- مفتاح الرسالة (sender + body hash + timestamp window) لمنع التكرار.

## الفهارس

فهارس على: customer phone، card serial، message dedupe key، transaction reference، wallet customer_id.

التفاصيل التنفيذية في `lib/data/database/app_database.dart`.
