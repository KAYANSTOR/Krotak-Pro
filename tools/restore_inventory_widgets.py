#!/usr/bin/env python3
"""Restore full inventory_widgets.dart from split gzip+b64 parts."""
from pathlib import Path
import base64, gzip, sys

parts = []
for i in range(4):
    p = Path(f'tools/inv_p{i}.b64')
    if not p.exists():
        print(f'Missing {p}', file=sys.stderr)
        sys.exit(1)
    parts.append(p.read_text().strip())

b64 = ''.join(parts)
raw = gzip.decompress(base64.b64decode(b64))
out = Path('lib/ui/screens/inventory_widgets.dart')
out.write_bytes(raw)
print(f'Restored {out} size={out.stat().st_size}')

text = out.read_text()
assert 'class _CategoryChip' in text
assert 'class _StatusChip' in text
assert 'class _TicketCard' in text
assert 'class _Header' in text
assert 'إدارة الكروت' in text
print('inventory_widgets restored OK')
