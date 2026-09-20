#!/usr/bin/env python3
from pathlib import Path
parts = [Path(f'tools/s2_{i}.txt').read_text() for i in range(6)]
script = ''.join(parts)
Path('tools/patch_phase2_ui.py').write_text(script)
print('assembled', len(script))
import subprocess, sys
r = subprocess.run([sys.executable, 'tools/patch_phase2_ui.py'])
raise SystemExit(r.returncode)
