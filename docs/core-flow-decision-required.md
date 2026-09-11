# Core Flow Decision — Amount to Card Category

**Status:** Confirmed business rule  
**Base:** `main` at `26ea5d1dcd47efd7348faaac810befc0e62e73fc`  
**Scope:** Core Business Flow only. No Dashboard Navigation or Post-v1 changes.

## Confirmed rule

For an incoming transfer, the parsed transfer amount is the selector for the card catalog.

```text
Incoming SMS
→ Parse
→ Resolve Customer
→ Transfer Amount
→ Find active CardCategory where faceValue == Transfer Amount
→ Reserve available Card from that category
→ Credit customer by the incoming transfer reference (idempotent)
→ Send card credentials to resolved delivery phone
→ Persist SMS delivery success state
→ Complete the same reserved Sale using stable operationId
→ Mark card Sold
→ Record Sale Ledger
→ Audit
```

The card category must already exist in the application's current card catalog. The processor must not create categories, use hardcoded category IDs, choose the first category, or invent a separate mapping.

## Matching semantics

The match is exact on both minor monetary units and currency code. If zero active categories match, the transfer is rejected as `unmatched_amount`. If more than one active category matches, the transfer is rejected as `ambiguous_amount_category` rather than selecting arbitrarily.

If the matching category has no available card, the operation is rejected as `out_of_stock`. No customer credit is created in either of these pre-reservation failure cases.

## Reservation and financial commit

A card reservation is distinct from a sale. The reservation is stable for the transfer operation (`transfer-reservation:<operationId>`) and is held while SMS delivery is attempted.

The incoming transfer credit is idempotent by the transfer reference. The sale uses the same stable operation identity on retry.

The financial sale commit happens only after the native `MessageSender` reports successful SMS delivery. The existing `LocalSaleService` is extended only with a narrow reserved-card completion boundary so the transfer flow does not perform a second reservation.

## Delivery state and recovery

No parallel SMS provider or commercial architecture is introduced.

The existing `MessageSender` / `SmsBridge` boundary is used through `NativeMessageSender`.

Because the repository already has `AuditLogRepository` but does not have a delivery-state table, `sms_delivery_succeeded` is persisted as an audit event containing `operationId`, `cardId`, `categoryId`, `reservationId`, and destination. Recovery checks this event before attempting another send.

If SMS delivery succeeds but sale commit fails, the card reservation is not released. Recovery completes the same reserved sale with the same operationId. If the reservation has expired, recovery may safely re-reserve the same card only while it remains available and in the original category; otherwise it stops rather than selling or sending another card.

## Existing architecture reused

- `IncomingSmsHandler`
- `LocalMessageParser`
- `LocalCustomerIdentityResolver`
- `LocalTransferProcessor`
- `CardCategoryRepository`
- `LocalCardInventoryService`
- `LocalCardRepository`
- `LocalSaleService`
- `MessageSender`
- `NativeMessageSender`
- `SmsBridge`
- `LocalTransactionRepository`
- `LocalAuditLogRepository`
- `DriftUnitOfWork`

## Required invariants

- Same SMS / same operation must not create a second Sale or Ledger entry.
- SMS retry after a failed send must not create duplicate financial effects.
- A card can be Sold only from the reservation owned by that transfer operation.
- A concurrent operation cannot consume the same available card twice because card reservation is an atomic status transition.
- Reverse Sale restores the card and links the reversal transaction to the original sale transaction.
- Rejected/failed terminal states survive financial rollback.

## Verification required before P0 Ready

```text
dart analyze lib test
flutter analyze --no-fatal-infos
flutter test
```

P0 is not considered Ready until the current branch passes all three checks and the integration tests prove amount matching, reservation, delivery, sale, ledger, audit, retry, concurrency, and reversal behavior.
