# نموذج المجال (Domain Model)

## الكيانات

- Customer, Wallet, CardCategory, Card, Message, Transaction, AuditLog, Setting, License
- Money (value object)
- Ledger لتجميع حركات الرصيد

## الخدمات

- LocalCustomerService
- LocalCustomerBalanceService
- LocalCatalogServices (فئات)
- LocalCardInventoryService
- LocalSaleService (بيع من الرصيد + عكس)

## Unit of Work

`DriftUnitOfWork` يضمن ذرية العمليات المالية والمخزنية عبر transaction واحدة.

## القواعد

انظر business-rules.md.
