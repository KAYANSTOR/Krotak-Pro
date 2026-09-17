# Phase 4 — Delivery worker (15-minute confirm + safe resend)

## Goal

After Phase 3 commits the sale **before** SMS, failed deliveries must:

1. Retry sending the **same** voucher (same card serial/code).
2. Never auto-issue a second card.
3. Respect max **3** attempts and **15-minute** confirm-pending timeout (screenshot rules).

## Component

`lib/domain/services/message_delivery_worker.dart` — `MessageDeliveryWorker.tick()`

### Candidate messages

- `failed`
- `sending`
- `pending`

### Eligibility

- Has audit `voucher_committed` with complete payload (`cardId`, `reservationId`, `categoryId`, `destination`)
- Does **not** already have `sms_delivery_succeeded`
- Due by retry schedule **or** confirm timeout (≥ 15 minutes since commit) **or** first attempt after failure (`attempts == 0`)

### Actions

| Outcome | Behavior |
|---------|----------|
| SMS ok | Append `sms_delivery_succeeded`, status → `processed`, clear retry |
| SMS fail | Append `sms_delivery_failed`, `recordFailure` (may → `failedMaxAttempts`) |
| Already sent | status → `processed`, clear retry |

## Integration

Call `MessageDeliveryWorker.tick()`:

- On app resume (alongside `LocalMessageRecoveryService.recoverPending`)
- On a periodic timer (e.g. every 1–5 minutes while foregrounded)

Do **not** call `reserveAvailableCard` from this worker.

## Tests

`test/services/message_delivery_worker_test.dart`

## Follow-ups

- Wire into composition root / UI resume path
- Expand `pendingProcessing()` to include `sending` if recovery should also see those rows
