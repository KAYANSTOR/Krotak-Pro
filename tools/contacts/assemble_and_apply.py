#!/usr/bin/env python3
from pathlib import Path
import base64
import subprocess
import sys

parts = sorted(Path('tools/contacts').glob('part_*.b64'))
if not parts:
    raise SystemExit('no part_*.b64 found')
data = ''.join(p.read_text().strip() for p in parts)
script = Path('tools/contacts/apply_contacts_identity.py')
script.write_bytes(base64.b64decode(data))
print('assembled', script.stat().st_size)
rc = subprocess.call([sys.executable, str(script)])
raise SystemExit(rc)
