# Phase 0 — Baseline Freeze Report

**Date:** 2026-09-17  
**Repository:** KAYANSTOR/net-flutter  
**Reference commit (main):** `95865c90fce7bea1dc926b36db08b77bd3066548`  
**Working branch:** `plan/phase-0-1-contracts-foundation`

## 1. Environment note

Flutter / Dart tooling is **not available** in the current analysis sandbox. Baseline for `flutter analyze` and `flutter test` must be established via GitHub Actions CI on this branch (see `.github/workflows/ci.yml`).

Expected CI steps (from existing workflow):
- `flutter pub get`
- `flutter analyze --no-fatal-infos`
- `flutter test`
- `flutter build apk --release` (or debug)

## 2. File inventory (high level)

| Area | Path | Notes |
|------|------|-------|
| Domain entities | `lib/domain/entities/` | Customer, Card, Sale, Transaction, Message, Advance, Wallet, POS, Promotion, Setting, License, Audit, Broadcast |
| Domain repositories (contracts) | `lib/domain/repositories/repositories.dart` | Abstract interfaces returning `Result<T>` |
| Unit of Work | `lib/domain/repositories/unit_of_work.dart` | Single `run` method |
| Domain services | `lib/domain/services/` | Sale, Settlement, Advance, Message parser/retry/recovery, Inventory, Backup, License, Unified payment engine, etc. |
| Data / Drift | `lib/data/` | Local*Repository implementations |
| Application | `lib/application/` | AppContainer, IncomingSmsHandler, IncomingNotificationHandler |
| Platform / Android bridge | `lib/platform/`, `android/.../SmsReceiver.kt` | SMS / notification / diagnostics bridges |
| UI | `lib/ui/` | Dashboard, messages, inventory, reports, settings, pending/rejected screens |
| Tests | `test/` (~40 Dart files) | Domain, services, widget, database, local repositories |

Approximate tracked files at baseline: **317**.

## 3. Core contracts snapshot

### Result
```dart
sealed class Result<T> { ... }
final class Success<T> extends Result<T> { final T value; }
final class Failure<T> extends Result<T> { final AppFailure error; }
final class AppFailure { final String code; final String message; }
```

### MessageProcessingStatus (current)
```dart
enum MessageProcessingStatus { received, parsed, processed, rejected, failed }
```

**Gap vs plan:** plan requires also `pending`, `sending`, `failedMaxAttempts`, `recovered` (or equivalent names). State machine transitions are not yet centralized.

### CardStatus
```dart
enum CardStatus { available, reserved, sold, disabled, expired }
```
Reservation model exists (`CardReservation` with id / timestamps). Atomic reserve + sale + ledger still needs hardening (Phase 2–3).

### CustomerRepository (excerpt)
- `findById`, `findByIdentifier`, `search`, `listIdentifiers`, `save`, `saveIdentifier`
- No `findByPhone` name; identifier-based lookup covers phone/account.

### MessageRepository
- `save`, `findById`, `findByExternalReference`, `pendingProcessing`, `listByStatus`, `listRecent`, `updateStatus`
- No explicit `findByDedupeKey` / fingerprint uniqueness at DB level yet (to be enforced in Phase 2).

### UnitOfWork
- Present but usage across sale/reservation/settlement paths must be audited and made mandatory for financial steps.

## 4. Known gaps (from conversion plan) — priority order

1. **Contract stability** — Fakes in tests are local and may drift from interfaces; no single shared fake package.
2. **Message state machine** — incomplete relative to operational statuses in screenshots.
3. **Idempotency / uniqueness** — message fingerprint, operation reference, reservationId, settlement reference need DB unique constraints + concurrent tests.
4. **Atomic financial workflow** — reserve → sale/ledger → delivery task must be one UnitOfWork (or compensable workflow).
5. **Android runtime proof** — out of scope for pure code phase; device gates remain Phase 5 / Phase 12 style.
6. **Encrypted backup + safe restore** — LocalBackupService exists; full AES-GCM + temp DB validation still required.

## 5. Phase 0 exit criteria

- [x] Reference commit frozen (`95865c9`)
- [x] Working branch created
- [x] Conversion plan committed under `docs/`
- [x] This baseline report committed
- [ ] CI green on the working branch (analyze + test)
- [ ] Contracts document published (next commit on this branch)

## 6. Immediate next (Phase 1)

1. Publish `docs/contracts.md` listing every repository + service public method.
2. Align `MessageProcessingStatus` with the operational set from the plan (additive, with migration notes).
3. Introduce shared test fakes that implement the exact interfaces.
4. Fix any compile / analyze / test failures revealed by CI.
5. Do **not** add new UI features or Post-V1 work until contracts + tests are green.

---
*Generated as part of conversion-plan execution. No production business logic changed in this commit.*
