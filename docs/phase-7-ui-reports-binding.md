# Phase 7 — UI & reports binding (first slice)

## Goal

Connect operator surfaces to **real Domain read-models** after Phases 1–6 stabilized the message/sale core.

## What landed

### OpsReportService

`lib/domain/services/ops_report_service.dart`

Single snapshot for:

- Daily / monthly completed sales (count + minor units)
- Available cards
- Recent completed transactions count
- Message pipeline: rejected, open pipeline, sending, failed, failedMaxAttempts

Used by **Reports hub** (`ReportsScreen`).

### Rejection codes ↔ UI

- `RejectionCodeLabels` — Arabic labels for all 13 screenshot codes
- `RejectionCategories.fromAuditAction` maps both legacy audit actions and `RejectionCodes.*`

### Reports hub

- Sectioned tiles: sales/inventory + message pipeline
- Deep links to existing report/message screens
- No mock numbers

## Tests

`test/services/ops_report_service_test.dart`

## Follow-ups

- Drive dashboard metrics through the same `OpsReportService` (shared cache / ValueNotifier)
- Export CSV for sales period report
- Show `RejectionCodeLabels` chip text on rejected message cards when payload carries domain code
