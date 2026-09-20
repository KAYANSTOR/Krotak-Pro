#!/usr/bin/env python3
import base64, gzip, pathlib
root = pathlib.Path('.')
parts = sorted(root.glob('tools/prov_*.b64'))
if not parts:
    raise SystemExit('no prov chunks')
raw = ''.join(p.read_text().strip() for p in parts)
blob = gzip.decompress(base64.b64decode(raw))
i = 0
data = blob
written = []
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
    written.append((path, len(content)))
for path, n in written:
    print('wrote', path, n)
text = (root / 'lib/domain/entities/customer.dart').read_text()
assert 'provisional' in text
text = (root / 'lib/domain/services/local_transfer_processor.dart').read_text()
assert 'CustomerStatus.provisional' in text
assert 'ledger_account_auto_provisioned' in text
print('VERIFY OK')
