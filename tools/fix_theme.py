import base64
from pathlib import Path
a = Path('tools/net_theme_a.b64').read_text().strip()
b = Path('tools/net_theme_b.b64').read_text().strip()
data = base64.b64decode(a + b)
Path('lib/ui/theme/net_theme.dart').write_bytes(data)
text = data.decode()
assert 'FlexSchemeColor(J' not in text
assert 'google_fonts' not in text
print('wrote', len(data), 'ok')
