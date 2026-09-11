# NET Flutter

تطبيق NET لإدارة بيع الكروت والشحنات على Android، مبني بـ Flutter مع قاعدة بيانات محلية (Drift) ومعالجة رسائل SMS.

## الحالة الحالية

- تهيئة المشروع + الوثائق والخطة
- كيانات Domain وعقود المستودعات
- مخطط Drift المحلي + المستودعات المحلية
- خدمات العملاء والمحافظ والفئات والمخزون
- البيع من الرصيد وعكس العملية + Ledger + Unit of Work
- اختبارات الوحدة والتكامل المحلي

الخطوة التالية: `MessageParser` و `TransferProcessor` ثم Android SMS Receiver.

انظر [docs/progress.md](docs/progress.md) و [docs/implementation-plan.md](docs/implementation-plan.md).
