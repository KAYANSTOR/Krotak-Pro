from pathlib import Path
import base64, gzip

inv_path = Path('tools/inventory_widgets.dart.gz.b64')
gz = base64.b64decode(inv_path.read_text().strip())
Path('lib/ui/screens/inventory_widgets.dart').write_bytes(gzip.decompress(gz))
print('inventory', Path('lib/ui/screens/inventory_widgets.dart').stat().st_size)

inv = Path('lib/ui/screens/inventory_widgets.dart').read_text()
assert 'class _TicketCard' in inv and 'class _Header' in inv
print('inventory restored ok')

p = Path('lib/domain/services/local_catalog_services.dart')
t = p.read_text()
t2 = t.replace("packageName: 'com.ama.wecashmobileapp'", "packageName: 'com.wecash.jawali'")
if t2 != t:
    p.write_text(t2)
    print('jawali package updated')
else:
    print('jawali already', 'com.wecash.jawali' in t)
