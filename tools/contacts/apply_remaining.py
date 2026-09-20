#!/usr/bin/env python3
import base64, gzip, pathlib
ROOT = pathlib.Path(__file__).resolve().parent
FILES = {
  "lib/domain/services/local_transfer_processor.dart": "lib__domain__services__local_transfer_processor_dart.b64",
  "android/app/src/main/kotlin/com/kayan/net_app/MainActivity.kt": "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt.b64",
}
for dest, name in FILES.items():
    data = gzip.decompress(base64.b64decode((ROOT / name).read_text().strip()))
    p = pathlib.Path(dest)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    print("wrote", dest, len(data))
