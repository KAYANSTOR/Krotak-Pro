#!/usr/bin/env python3
import base64, gzip, pathlib
root = pathlib.Path("tools/contacts/payload")

def load(name):
    p = root / name
    if p.exists():
        return p.read_text().strip()
    a = root / name.replace(".b64", "__a.b64")
    b = root / name.replace(".b64", "__b.b64")
    if a.exists() and b.exists():
        return a.read_text().strip() + b.read_text().strip()
    raise SystemExit("missing " + name)

FILES = [
  ("lib/application/app_container_impl.dart", [
    "lib__application__app_container_impl_dart__00.b64",
    "lib__application__app_container_impl_dart__01.b64",
  ]),
  ("android/app/src/main/kotlin/com/kayan/net_app/MainActivity.kt", [
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__00.b64",
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__01.b64",
  ]),
  ("lib/domain/services/local_transfer_processor.dart", [
    "lib__domain__services__local_transfer_processor_dart__00.b64",
    "lib__domain__services__local_transfer_processor_dart__01.b64",
    "lib__domain__services__local_transfer_processor_dart__02.b64",
  ]),
]

for path, names in FILES:
    b64 = "".join(load(n) for n in names)
    data = gzip.decompress(base64.b64decode(b64))
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    print("wrote", path, len(data))
print("CONTACTS_FILES_OK")
