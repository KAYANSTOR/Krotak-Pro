import base64, gzip
from pathlib import Path

def write_gz_b64(b64path, dest):
    gz = base64.b64decode(Path(b64path).read_text().strip())
    data = gzip.decompress(gz)
    Path(dest).write_bytes(data)
    print(dest, len(data))

write_gz_b64('tools/inventory_widgets.dart.gz.b64', 'lib/ui/screens/inventory_widgets.dart')
write_gz_b64('tools/wallets_pos.dart.gz.b64', 'lib/ui/screens/wallets_pos_screen.dart')

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
assert '_WalletsHeader' in wal and 'WalletSourceMode.notification' in wal
print('verified ok')
