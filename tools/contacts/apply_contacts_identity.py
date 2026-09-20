#!/usr/bin/env python3
"""Contacts-based customer identity on auto-provision.

Rule:
  phone found in device contacts (+ non-empty name) -> CustomerStatus.active with contact name
  otherwise -> CustomerStatus.provisional (ledger only)
"""
from pathlib import Path

def must_replace(path, old, new, label, skip_if=None):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if skip_if and skip_if in text:
            print("skip already", path, label)
            return
        raise SystemExit("MISSING marker in %s: %s" % (path, label))
    c = text.count(old)
    if c != 1:
        raise SystemExit("Expected 1 occurrence of %s in %s, found %d" % (label, path, c))
    p.write_text(text.replace(old, new, 1))
    print("patched", path, label)

# ---- 1) Domain contract ----
Path("lib/domain/services/contact_directory.dart").write_text(
    "/// Device phone-book lookup for customer identity decisions.\n"
    "///\n"
    "/// When a deposit arrives from an unknown phone:\n"
    "/// - found in contacts => full [CustomerStatus.active] with contact display name\n"
    "/// - not found / no permission => [CustomerStatus.provisional] ledger-only\n"
    "abstract interface class ContactDirectory {\n"
    "  /// Returns a match when [phone] exists in device contacts with a display name.\n"
    "  Future<DeviceContactMatch?> findByPhone(String phone);\n"
    "}\n"
    "\n"
    "final class DeviceContactMatch {\n"
    "  const DeviceContactMatch({\n"
    "    required this.displayName,\n"
    "    required this.phone,\n"
    "  });\n"
    "\n"
    "  final String displayName;\n"
    "  final String phone;\n"
    "}\n"
)
print("wrote contact_directory.dart")
