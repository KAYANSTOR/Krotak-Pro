#!/usr/bin/env python3
import base64, gzip, pathlib
root = pathlib.Path('.')

def restore(prefix, dest, n=3):
    parts = [root / f'tools/{prefix}_{i}.b64' for i in range(n)]
    if not all(p.exists() for p in parts):
        raise SystemExit(f'missing {prefix} chunks')
    raw = ''.join(p.read_text().strip() for p in parts)
    data = gzip.decompress(base64.b64decode(raw))
    out = root / dest
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print('wrote', dest, len(data))

restore('p2c', 'lib/ui/screens/customers_screen.dart')
restore('p2d', 'lib/ui/screens/customer_detail_screen.dart')
assert 'isProvisional' in (root/'lib/ui/screens/customers_screen.dart').read_text()
assert '_promoteToCustomer' in (root/'lib/ui/screens/customer_detail_screen.dart').read_text()
print('PHASE2_UI_OK')
