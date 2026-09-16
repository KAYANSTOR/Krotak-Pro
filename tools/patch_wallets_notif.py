from pathlib import Path
p = Path('lib/domain/services/local_catalog_services.dart')
t = p.read_text()
t2 = t.replace(
    "sourceMode: WalletSourceMode.sms, packageName: 'com.ama.wecashmobileapp'",
    "sourceMode: WalletSourceMode.notification, packageName: 'com.ama.wecashmobileapp'",
)
t2 = t2.replace(
    "sourceMode: WalletSourceMode.sms, packageName: 'com.one.onecustomer'",
    "sourceMode: WalletSourceMode.notification, packageName: 'com.one.onecustomer'",
)
t2 = t2.replace(
    "sourceMode: WalletSourceMode.sms, packageName: 'co.ysys.floosak'",
    "sourceMode: WalletSourceMode.notification, packageName: 'co.ysys.floosak'",
)
if t2 == t:
    print('no changes or already applied')
else:
    p.write_text(t2)
    print('wallets notification packages applied')
print('jaib notification', "WalletSourceMode.notification, packageName: 'com.ahd.jaib'" in t2)
