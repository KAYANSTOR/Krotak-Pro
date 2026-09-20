# Phase engine-hotpath

## Slice 1
- Provisional sellable + category face-value cache 45s TTL

## Slice 2
- CardRepository.reserveFirstAvailable (category expire + LIMIT 1 + conditional UPDATE)
- Inventory prefers atomic; legacy fallback retained
- InMemoryCardRepository implements atomic reserve

Guarantees: sale-op idempotency, provisional ledger, SMS after commit, worker retry.
