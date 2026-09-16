import base64
from pathlib import Path

def from_parts(prefix, n, dest):
    parts = []
    for i in range(n):
        parts.append(Path(f'tools/{prefix}{i}.b64').read_text().strip())
    data = base64.b64decode(''.join(parts))
    Path(dest).write_bytes(data)
    print(dest, len(data))

from_parts('inv_part', 1, 'lib/ui/screens/inventory_widgets.dart')
from_parts('wal_part', 4, 'lib/ui/screens/wallets_pos_screen.dart')

p = Path('lib/domain/services/local_catalog_services.dart')
t = p.read_text()
t2 = t.replace("packageName: 'com.ama.wecashmobileapp'", "packageName: 'com.wecash.jawali'")
if t2 != t:
    p.write_text(t2)
    print('jawali package updated')
else:
    print('jawali already', 'com.wecash.jawali' in t)

inv = Path('lib/ui/screens/inventory_widgets.dart').read_text()
assert 'class _TicketCard' in inv
assert 'class _Header' in inv
print('inventory widgets verified')
wal = Path('lib/ui/screens/wallets_pos_screen.dart').read_text()
assert '_WalletsHeader' in wal
assert 'sourceMode == WalletSourceMode.notification' in wal
print('wallets verified')
