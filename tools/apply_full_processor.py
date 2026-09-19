#!/usr/bin/env python3
"""Assemble b64 chunks and write full LocalTransferProcessor + tests."""
from pathlib import Path
import base64
import sys

root = Path(__file__).resolve().parents[1]
tools = root / 'tools'

def assemble(prefix: str) -> bytes:
    parts = sorted(tools.glob(f'{prefix}_*.b64'))
    if not parts:
        raise SystemExit(f'no chunks for {prefix}')
    data = ''.join(p.read_text().strip() for p in parts)
    return base64.b64decode(data)

proc = assemble('xfer_full')
test = assemble('xfer_test')
proc_path = root / 'lib/domain/services/local_transfer_processor.dart'
test_path = root / 'test/services/message_parser_and_transfer_test.dart'
assert b'_canAutoProvision' in proc, 'missing auto-provision'
assert b'reserveAvailableCard' in proc, 'missing commercial path'
proc_path.write_bytes(proc)
test_path.write_bytes(test)
print('wrote', proc_path, 'bytes', len(proc))
print('wrote', test_path, 'bytes', len(test))
