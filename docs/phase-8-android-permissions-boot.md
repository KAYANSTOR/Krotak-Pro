# Phase 8 slice — Permissions, background, boot auto-start

## Changes

### AndroidManifest
- `READ_CONTACTS`
- `WAKE_LOCK`
- BootReceiver: `directBootAware`, `QUICKBOOT_POWERON` (some OEM reboot intents)

### BootReceiver
- Still writes `pending_recovery_after_boot`
- **Also launches `MainActivity`** after boot / package replace so the app returns without a manual open
- OEMs that block background activity starts still need the autostart settings step

### MainActivity
- `requestContacts` / `hasContactsPermission` on diagnostics channel
- `READ_CONTACTS` runtime request (`REQUEST_CONTACTS = 1004`)

### Flutter
- `SystemDiagnosticsBridge.requestContactsPermission`
- `PermissionsOnboarding` **v6**:
  - جهات الاتصال
  - العمل في الخلفية (استثناء البطارية)
  - التشغيل التلقائي بعد إعادة تشغيل الهاتف (OEM settings + optional continue)
- Clean logs: confirmation dialog before smart purge

## Manual acceptance
1. Fresh install → onboarding asks for SMS, notifications, **contacts**, notification listener, battery, **autostart**, phone state
2. Reboot device → NET activity opens (or OEM requires autostart whitelist first)
3. Smart purge shows confirmation before deleting retained messages
