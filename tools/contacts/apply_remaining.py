#!/usr/bin/env python3
import base64, gzip, pathlib
ROOT = pathlib.Path(__file__).resolve().parent

def load_b64(parts):
    return "".join((ROOT / p).read_text().strip() for p in parts)

FILES = {
  "lib/domain/services/local_transfer_processor.dart": [
    "lib__domain__services__local_transfer_processor_dart__a.b64",
    "lib__domain__services__local_transfer_processor_dart__b.b64",
  ],
  "android/app/src/main/kotlin/com/kayan/net_app/MainActivity.kt": [
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__q0.b64",
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__q1.b64",
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__q2.b64",
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__q3.b64",
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__q4.b64",
    "android__app__src__main__kotlin__com__kayan__net_app__MainActivity_kt__q5.b64",
  ],
}
for dest, parts in FILES.items():
    data = gzip.decompress(base64.b64decode(load_b64(parts)))
    p = pathlib.Path(dest)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    print("wrote", dest, len(data))
