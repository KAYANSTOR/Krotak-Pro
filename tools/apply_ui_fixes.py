from pathlib import Path
import base64, gzip

gz = base64.b64decode(Path('tools/inventory_widgets.dart.gz.b64').read_text().strip())
Path('lib/ui/screens/inventory_widgets.dart').write_bytes(gzip.decompress(gz))
print('inventory', Path('lib/ui/screens/inventory_widgets.dart').stat().st_size)

parts = [Path(f'tools/wal_src_{i}.dart.part').read_text() for i in range(3)]
Path('lib/ui/screens/wallets_pos_screen.dart').write_text(''.join(parts))
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
assert '_WalletsHeader' in wal and 'WalletSourceMode.notification' in wal
print('verified ok')
