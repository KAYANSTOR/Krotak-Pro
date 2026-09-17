# Phase 3 — Atomic commercial workflow (first slice)

## Problem (pre-change)

Transfer commercial path ordered as:

1. reserve card
2. credit customer
3. **send SMS**
4. completeReservedSale (ledger + mark sold)

If SMS failed, the code **released the reservation**, so a retry could sell a **second** card while the customer already had credit — violating the help-center rule (no automatic second voucher).

## Target order (screenshots + conversion plan)

1. Eligibility / parse / blacklist / category match
2. Reserve card (atomic inventory UoW)
3. Credit inbound transfer
4. **Commit sale + ledger** (`completeReservedSale` inside `UnitOfWork`)
5. Persist `voucher_committed` audit (card + reservation + operationId)
6. Send SMS
7. On SMS success → `sms_delivery_succeeded` + message `processed`
8. On SMS failure → message `failed` / retry queue; **do not** release card; recovery uses `voucher_committed` or `sms_delivery_succeeded` state

## What landed

- `LocalTransferProcessor` commercial path reordered to commit before send.
- New audit action: `voucher_committed`.
- `_deliveryState` recovers from `voucher_committed` **or** `sms_delivery_succeeded`.
- SMS failure no longer calls `releaseReservation`.

## Still open (later Phase 3/4)

- Wrap credit + reserve + completeSale in a **single** outer UnitOfWork (today reserve and complete each use their own UoW).
- Explicit delivery job table / Worker with 15-minute confirm timeout.
- Promotion / points posting inside the same financial boundary.

## Tests

Existing core flow integration tests still apply. Recovery tests that seed `sms_delivery_succeeded` remain valid; new recovery can also seed `voucher_committed`.
