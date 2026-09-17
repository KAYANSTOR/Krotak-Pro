# Phase 2 — Idempotency indexes (schema v3)

**Branch:** `main`  
**schemaVersion:** `3`

## What landed

Unique indexes (created on fresh install and on upgrade from v2):

| Index | Table | Purpose |
|-------|-------|--------|
| `idx_customer_identifiers_value` | customer_identifiers | One customer per phone/identifier value |
| `idx_cards_serial_number` | cards | No duplicate serials |
| `idx_cards_secret_code` | cards | No duplicate secrets |
| `idx_cards_reservation_id` | cards (partial) | Same reservation id cannot bind two cards |
| `idx_incoming_messages_external_reference` | incoming_messages (partial) | Dedupe inbound message by bank/wallet reference |
| `idx_transactions_reference` | transactions (partial) | One ledger row per commercial reference |
| `idx_sales_card_id` | sales | One sale row per card (prevents double sell at DB layer) |

Partial indexes (`WHERE … IS NOT NULL`) allow multiple NULL values (SQLite semantics).

## Explicitly deferred (needs Drift codegen / build_runner)

- Dedicated `message_fingerprint` column on `incoming_messages`
- Dedicated `operation_reference` column on `sales`
- Domain `findByFingerprint` on `MessageRepository`

Until those land, services must continue to use `externalReference` / payment fingerprint keys that map into the unique columns above.

## Acceptance tests

See `test/data_database_test.dart` — unique constraints for reservation, message reference, transaction reference, and one sale per card.

## Next (Phase 3)

Atomic UnitOfWork path: eligibility → reserve → sale + ledger → delivery task, relying on these indexes under concurrent load.
