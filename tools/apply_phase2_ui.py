#!/usr/bin/env python3
import base64, gzip, pathlib
root = pathlib.Path('.')
parts = [root / f'tools/p2ui_{i}.b64' for i in range(4)]
if not all(p.exists() for p in parts):
    raise SystemExit('missing p2ui chunks')
raw = ''.join(p.read_text().strip() for p in parts)
blob = gzip.decompress(base64.b64decode(raw))
i = 0
data = blob
while i < len(data):
    nl = data.find(b'\n', i)
    path = data[i:nl].decode()
    i = nl + 1
    nl = data.find(b'\n', i)
    length = int(data[i:nl].decode())
    i = nl + 1
    content = data[i:i+length]
    i = i + length
    if data[i:i+1] == b'\n':
        i += 1
    out = root / path
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(content)
    print('wrote', path, len(content))
assert 'isProvisional' in (root/'lib/ui/screens/customers_screen.dart').read_text()
assert '_promoteToCustomer' in (root/'lib/ui/screens/customer_detail_screen.dart').read_text()
print('PHASE2_UI_OK')
