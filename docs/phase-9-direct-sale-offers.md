# Phase 9 — البيع المباشر والعروض

**تاريخ:** 2026-09-17  
**الحالة:** منفّذة برمجياً — التأكيد البصري على جهاز حقيقي

## النطاق

- البيع المباشر بأربع طرق عبر `DirectSaleSheet` + `SaleService.sellManual`: نقدي، آجل، هدية، نقطة بيع.
- شاشة العروض: تبويب نشطة/معطّلة، إنشاء، تعديل، تعطيل، حذف — كلها عبر `LocalPromotionCatalog`.
- لا Mock: الفئات من `CardCategoryRepository` والعروض من إعداد الكتالوج المحلي.

## الملفات

| ملف | دور |
|-----|-----|
| `lib/ui/widgets/dashboard/direct_sale_sheet.dart` | حوار البيع المباشر |
| `lib/ui/screens/direct_sale_screen.dart` | مسار عميق للبيع |
| `lib/ui/screens/offers_screen.dart` | إدارة العروض |
| `lib/domain/services/local_promotion_catalog.dart` | `create` / `update` / `setStatus` / `delete` |
| `test/services/promotion_catalog_test.dart` | إنشاء وتعديل ورفض العنوان الفارغ |

## خارج النطاق

- تحقق جهاز نهائي (المرحلة 11).
- تغيير قواعد صرف المكافأة التلقائي (مراحل 14–17 مكتملة مسبقاً).
