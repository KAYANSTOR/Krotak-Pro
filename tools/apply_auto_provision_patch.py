#!/usr/bin/env python3
from pathlib import Path
import base64

def decode_full(src, dest):
    p = Path(src)
    if not p.exists():
        return False
    data = p.read_text().strip()
    if not data or data.startswith('PLACEHOLDER') or data.startswith('WILL_'):
        return False
    Path(dest).write_bytes(base64.b64decode(data))
    return True

ok1 = decode_full('tools/auto_provision_processor.b64', 'lib/domain/services/local_transfer_processor.dart')
ok2 = decode_full('tools/auto_provision_test.b64', 'test/services/message_parser_and_transfer_test.dart')
if not ok1:
    parts = sorted(Path('tools').glob('auto_p_proc_*.b64'))
    if not parts:
        raise SystemExit('no processor payload')
    raw = ''.join(p.read_text().strip() for p in parts)
    Path('lib/domain/services/local_transfer_processor.dart').write_bytes(base64.b64decode(raw))
if not ok2:
    parts = sorted(Path('tools').glob('auto_p_test_*.b64'))
    if not parts:
        raise SystemExit('no test payload')
    raw = ''.join(p.read_text().strip() for p in parts)
    Path('test/services/message_parser_and_transfer_test.dart').write_bytes(base64.b64decode(raw))

p = Path('lib/domain/services/local_transfer_processor.dart').read_text()
assert '_autoProvisionCustomer' in p, 'processor missing auto provision'
t = Path('test/services/message_parser_and_transfer_test.dart').read_text()
assert 'auto-provisions unknown phone' in t, 'test missing auto provision case'
print('OK processor', Path('lib/domain/services/local_transfer_processor.dart').stat().st_size)
print('OK test', Path('test/services/message_parser_and_transfer_test.dart').stat().st_size)
