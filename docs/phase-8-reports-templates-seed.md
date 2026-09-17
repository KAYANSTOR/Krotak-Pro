# Reports hub UI + default wallet templates

## Reports / monitoring hub

`ReportsScreen` matches the product video layout:

- Section **الرسائل**: rejected, pending pipeline, failed/exhausted
- Section **التقارير**: transactions log, sales report, POS accounts, detailed sales
- Counts from `OpsReportService` (real repositories)

## Default parse templates

On bootstrap (after `ensureDefaultWallets`):

`DefaultWalletTemplatesSeeder` inserts active templates for:

| Wallet | Variants |
|--------|----------|
| جيب / JAIB | Arabic shared, phone-only, English received |
| جوالي / JAWALI | Arabic shared, phone-only |
| ون كاش | Arabic shared, generic SMS |
| فلوسك | Arabic shared, generic SMS |

Stable ids: `tpl-default-{sender}-{variant}`. Flag: `default_wallet_templates_seeded_v1`.

**New wallets** still require operator templates via the wizard.

## Direct sale

Unchanged path: `DirectSaleSheet` → `saleService.sellManual` (real domain). Entry: `DirectSaleScreen` / dashboard.
