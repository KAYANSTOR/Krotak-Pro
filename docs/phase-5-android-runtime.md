# Phase 5 — Android runtime (first slice)

## Goal

Ensure device integration supports continuous SMS commercial operation:

1. SMS receive/send permissions and dual-SIM probe (existing)
2. Battery optimization / auto-start settings helpers (existing)
3. **Boot recovery hint** so post-reboot app sessions run recovery/delivery promptly
4. **App resume** triggers an immediate recovery + delivery worker pass

## What landed

### BootReceiver

- `android/.../BootReceiver.kt`
- Registered for `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`
- Writes `pending_recovery_after_boot` to SharedPreferences (no auto UI launch)
- `MainActivity.configureFlutterEngine` consumes the flag (log)

### Flutter lifecycle

- `AppContainer.runRecoveryPass()` → same path as the 1-minute timer (`recoverPending` + `deliveryWorker.tick`)
- `NetApp` observes `AppLifecycleState.resumed` and calls `runRecoveryPass()`

### Already present (inventory)

| Surface | Status |
|---------|--------|
| `RECEIVE_SMS` / `SEND_SMS` / `READ_SMS` | Manifest + MainActivity |
| `SmsReceiver` | Registered, high priority |
| `NotificationListener` | Wallet notifications |
| Dual SIM (`SubscriptionManager`) | Diagnostics probe |
| Battery optimization ignore request | Diagnostics bridge |
| OEM auto-start intents | Diagnostics bridge |
| `FOREGROUND_SERVICE` permission | Declared |

## Acceptance

- After reboot, opening the app runs recovery/delivery without waiting a full minute
- Returning to the app from background runs the same pass
- SMS reception still works via `SmsReceiver` independently of Flutter isolate state (when process not force-stopped)

## Follow-ups

- Optional: headless FlutterEngine / WorkManager for recovery without opening UI
- Foreground service while processing SMS backlog on restricted OEMs
- Explicit default-SMS-app flow only if product requires it
