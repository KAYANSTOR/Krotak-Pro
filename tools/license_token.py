#!/usr/bin/env python3
"""Issue Krotak Pro Ed25519 license tokens.

The private key must remain outside Git and outside the APK. The app only
contains the public key used to verify tokens.
"""
from __future__ import annotations

import argparse
import base64
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

PREFIX = "KRT1"
PRODUCT = "krotak-pro"


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def load_private(path: Path) -> Ed25519PrivateKey:
    raw = path.read_bytes()
    if len(raw) != 32:
        raise SystemExit("The private key must be exactly 32 raw Ed25519 bytes")
    return Ed25519PrivateKey.from_private_bytes(raw)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> None:
    parser = argparse.ArgumentParser(description="Issue a signed Krotak Pro license token")
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--license-id", required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--days", type=int)
    group.add_argument("--perpetual", action="store_true")
    parser.add_argument("--device")
    args = parser.parse_args()
    if args.days is not None and args.days <= 0:
        parser.error("--days must be greater than zero")

    now = datetime.now(timezone.utc).replace(microsecond=0)
    payload = {
        "v": 1,
        "product": PRODUCT,
        "id": args.license_id.strip(),
        "iat": iso(now),
        "exp": None if args.perpetual else iso(now + timedelta(days=args.days)),
    }
    if args.device:
        payload["device"] = args.device.strip()
    payload_bytes = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    signature = load_private(args.private_key).sign(payload_bytes)
    print(f"{PREFIX}.{b64(payload_bytes)}.{b64(signature)}")


if __name__ == "__main__":
    main()
