# Contacts-based customer identity

## Rule
When an inbound transfer phone is **not** already a customer:

| Device contacts | Result |
|-----------------|--------|
| Found with a display name | `CustomerStatus.active` + contact name |
| Not found / no permission | `CustomerStatus.provisional` (ledger only) |

## Also
If a provisional account later receives a transfer and the phone is now in
contacts, it is **promoted** to active and renamed from the contact
(`promoted_from_contacts` audit).

## Platform
- `lookupContactByPhone` on diagnostics channel (MainActivity)
- `ContactPickerBridge.findByPhone` / `lookupByPhone`
- Wired into `LocalTransferProcessor` via `ContactDirectory`

## Permissions
Requires `READ_CONTACTS` (onboarding phase 8). Without permission,
all unknown phones stay provisional (safe default).
