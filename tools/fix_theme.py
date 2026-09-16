import base64
from pathlib import Path
b64 = open('tools/net_theme.b64').read().strip()
Path('lib/ui/theme/net_theme.dart').write_bytes(base64.b64decode(b64))
print('wrote', Path('lib/ui/theme/net_theme.dart').stat().st_size)
