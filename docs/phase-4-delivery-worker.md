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

## Integration (wired)

`AppContainer.startBackgroundHandlers()` runs every **1 minute** (and once at start):

1. `recoveryService.recoverPending()` — reprocess received/parsed/failed commercial path
2. `deliveryWorker.tick()` — resend SMS for `voucher_committed` without success

Both respect `SettingKeys.autoRetryFailedMessages`.

Do **not** call `reserveAvailableCard` from this worker.

## Tests

`test/services/message_delivery_worker_test.dart`

## Follow-ups

- Optional: trigger an extra `tick()` on `AppLifecycleState.resumed` for faster recovery when returning to the app
