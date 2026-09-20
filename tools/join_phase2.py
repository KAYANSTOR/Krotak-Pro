#!/usr/bin/env python3
from pathlib import Path
root=Path('.')
def join(parts, dest):
    data=''.join((root/p).read_text() for p in parts)
    out=root/dest
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(data)
    print('wrote', dest, len(data))
join(['tools/cs_part1.dart','tools/cs_part2.dart'], 'lib/ui/screens/customers_screen.dart')
join(['tools/cd_part1.dart','tools/cd_part2.dart'], 'lib/ui/screens/customer_detail_screen.dart')
docs=root/'tools/p2docs_0.b64'
if docs.exists():
    import base64,gzip
    (root/'docs/phase-2-provisional-ui.md').write_bytes(gzip.decompress(base64.b64decode(docs.read_text().strip())))
else:
    (root/'docs').mkdir(exist_ok=True)
    (root/'docs/phase-2-provisional-ui.md').write_text('# Phase 2 provisional UI applied\n')
assert 'isProvisional' in (root/'lib/ui/screens/customers_screen.dart').read_text()
assert '_promoteToCustomer' in (root/'lib/ui/screens/customer_detail_screen.dart').read_text()
print('PHASE2_JOIN_OK')
