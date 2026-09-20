# Phase 8.2–8.4 — تقارير المبيعات وتسوية نقاط البيع

**تاريخ:** 2026-09-17  
**الحالة:** منفّذة برمجياً — التأكيد البصري على جهاز حقيقي

## النطاق

- 8.2 تقرير مبيعات حسب الفترة (يوم / شهر / مختار) من `SaleRepository.listCompletedBetween`.
- 8.3 حسابات نقاط البيع: مستحق أو رصيد مدفوع + وضع العمولة + معرّفات الربط.
- 8.4 مفتاح التسوية التلقائية + تسوية يدوية عبر `CustomerBalanceService.credit` (نفس دفتر العميل).

## الملفات

| ملف | دور |
|-----|-----|
| `lib/ui/screens/reports/sales_period_report_screen.dart` | تقرير الفترة |
| `lib/ui/screens/reports/pos_accounts_ledger_screen.dart` | حسابات نقاط البيع والتسوية |
| `lib/ui/screens/reports_screen.dart` | مركز التقارير |
| `lib/ui/routing/app_routes.dart` | `openSalesPeriodReport` / `openPosAccountsLedger` |

## خارج النطاق

- تغيير قواعد التسوية التلقائية في TransferProcessor.
- تدقيق بصري لشاشة الكروت (المرحلة 7).
