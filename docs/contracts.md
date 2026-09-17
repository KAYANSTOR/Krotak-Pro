# Domain Contracts — Phase 1 Baseline

**Branch:** `plan/phase-0-1-contracts-foundation`  
**Source of truth:** `lib/domain/repositories/repositories.dart`, `lib/domain/repositories/unit_of_work.dart`, `lib/core/result.dart`, service classes under `lib/domain/services/`.

This document freezes the public surface that implementations and test fakes must implement. Changes to method signatures require updating this file in the same PR.

## Result

```dart
sealed class Result<T> {}
final class Success<T> extends Result<T> { final T value; }
final class Failure<T> extends Result<T> { final AppFailure error; }
final class AppFailure { final String code; final String message; }
```

All repository and service public methods that can fail return `Future<Result<...>>` (or `Result` when synchronous).

## UnitOfWork

```dart
abstract interface class UnitOfWork {
  Future<Result<T>> run<T>(Future<Result<T>> Function() action);
}
```

Financial sequences (eligibility → reserve → sale/ledger → delivery task) must run inside a single `UnitOfWork.run` (or an explicit compensable workflow documented in Phase 3).

## Repositories

### CustomerRepository
- `Future<Result<Customer?>> findById(String id)`
- `Future<Result<Customer?>> findByIdentifier(String value)`
- `Future<Result<List<Customer>>> search(String query)`
- `Future<Result<List<CustomerIdentifier>>> listIdentifiers(String customerId)`
- `Future<Result<void>> save(Customer customer)`
- `Future<Result<void>> saveIdentifier(CustomerIdentifier identifier)`

### WalletRepository
- `findById`, `listAll`, `save`

### PointOfSaleRepository
- `findById`, `listAll`, `save`

### CardCategoryRepository
- `findById`, `listAll`, `save`

### CardRepository
- `findById`, `findBySerialNumber`
- `existingSerialsAmong`, `existingSecretsAmong`
- `findByCategory`, `findAvailableByCategory`, `listByStatus`
- `save`, `saveAll`
- `expireReservations`, `reserve`, `releaseReservation`, `markSold`, `restoreAvailable`

### TransactionRepository
- `append`, `findByCustomer`, `findByReference`, `listRecent`, `listCompleted`

### SaleRepository
- `save`, `findById`, `findByCustomer`, `listRecent`, `listCompletedBetween`

### AdvanceRepository
- `findOpenByCustomer`, `listByCustomer`, `findById`

### MessageRepository
- `save`, `findById`, `findByExternalReference`
- `pendingProcessing`, `listByStatus`, `listRecent`, `updateStatus`

### TransferTemplateRepository
- `listAll`, `listByWallet`, `findById`, `save`, `delete`

### LicenseRepository
- `getCurrent`, `save`

### SettingsRepository
- `find`, `save`

### AuditLogRepository
- `append`, `findByEntity`

## Message state machine

Enum: `MessageProcessingStatus`  
Values: `received`, `parsed`, `pending`, `sending`, `processed`, `failedMaxAttempts`, `rejected`, `recovered`, `failed`

Helper: `MessageStatusMachine` (`lib/domain/message_status_machine.dart`) — single place for allowed transitions and terminal/attention classification.

## Rules for Phase 1

1. Every new Fake in tests must implement the exact interface above (no missing methods, no extra required methods that production does not have).
2. Prefer shared fakes under `test/helpers/` over one-off classes when the same repository is faked in multiple tests.
3. Do not widen or narrow repository contracts in feature PRs without updating this document.
4. CI must stay green (`analyze` + `test`) on this branch before starting Phase 2 schema work.

## Next contract work

- [ ] Shared fake suite for Customer / Message / Card / Transaction / Sale / Audit
- [ ] Audit call sites of `UnitOfWork` for sale + reservation paths
- [ ] Add `findByDedupeKey` / fingerprint uniqueness only after schema Phase 2 decision
