# Phase 6 — Encrypted backup & smart maintenance

## Goal (screenshots)

1. Encrypted portable backup: **AES-GCM 256**, **PBKDF2 10_000**, **SHA-256** fingerprint, `.znet`
2. Password ≥ 4 characters
3. Restore must **not** reset license counters
4. Smart cleanup retention:
   - rejected → 30 days
   - processed (completed) → 3 days
   - failedMaxAttempts → 30 days
5. Never delete financial ledger (sales / transactions / cards)

## Components

| File | Role |
|------|------|
| `lib/domain/services/local_backup_service.dart` | `.znet` encrypt / decrypt / list |
| `lib/domain/services/local_maintenance_service.dart` | Retention purge |
| `MessageRepository.delete` | Required for purge |
| Clean logs screen | UI: «تنظيف السجلات المنتهية» |

## Backup envelope (`znet-backup-v1`)

```json
{
  "format": "znet-backup-v1",
  "kdf": "PBKDF2-HMAC-SHA256",
  "iterations": 10000,
  "cipher": "AES-256-GCM",
  "salt": "...",
  "nonce": "...",
  "ciphertext": "...",
  "mac": "...",
  "fingerprint": "sha256-hex"
}
```

Plaintext payload: settings snapshot only (no license entity).

## API notes

- `createBackup({required String password, String? label})` — breaking change vs plain export (password required)
- `restoreFromFile(file, {String? password})` — supports legacy plain `.json` and `.znet`

## Dependency

- `cryptography: ^2.7.0` in `pubspec.yaml`

## Follow-ups

- Full SQLite file export into the same envelope
- Automatic scheduled backups to `ZNet_Backups` external folder
- SmsParseLog retention (7 days) once parse-log table is first-class
