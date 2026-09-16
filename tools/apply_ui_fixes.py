from pathlib import Path
import base64, gzip

inv_path = Path('tools/inventory_widgets.dart.gz.b64')
if inv_path.exists():
    gz = base64.b64decode(inv_path.read_text().strip())
    Path('lib/ui/screens/inventory_widgets.dart').write_bytes(gzip.decompress(gz))
    print('inventory', Path('lib/ui/screens/inventory_widgets.dart').stat().st_size)

a = Path('tools/wc_a.b64').read_text().strip()
b = Path('tools/wc_b.b64').read_text().strip()
gz = base64.b64decode(a + b)
Path('lib/ui/screens/wallets_pos_screen.dart').write_bytes(gzip.decompress(gz))
print('wallets', Path('lib/ui/screens/wallets_pos_screen.dart').stat().st_size)

p = Path('lib/domain/services/local_catalog_services.dart')
t = p.read_text()
t2 = t.replace("packageName: 'com.ama.wecashmobileapp'", "packageName: 'com.wecash.jawali'")
if t2 != t:
    p.write_text(t2)
    print('jawali package updated')
else:
    print('jawali already', 'com.wecash.jawali' in t)

inv = Path('lib/ui/screens/inventory_widgets.dart').read_text()
assert 'class _TicketCard' in inv and 'class _Header' in inv
wal = Path('lib/ui/screens/wallets_pos_screen.dart').read_text()
assert 'إدارة المحافظ ونقاط البيع' in wal
print('verified ok')
