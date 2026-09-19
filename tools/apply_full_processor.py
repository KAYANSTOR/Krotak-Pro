#!/usr/bin/env python3
"""Assemble gzip+b64 chunks and restore full LocalTransferProcessor (+ tests if valid)."""
from pathlib import Path
import base64
import gzip

def assemble(prefix: str) -> bytes:
    parts = sorted(Path('tools').glob(f'{prefix}_*.b64'))
    if not parts:
        raise SystemExit(f'no chunks for {prefix}')
    raw = ''.join(p.read_text().strip() for p in parts)
    return gzip.decompress(base64.b64decode(raw))

def main() -> None:
    proc = assemble('xf')
    Path('lib/domain/services/local_transfer_processor.dart').write_bytes(proc)
    text = proc.decode('utf-8')
    assert '_autoProvisionCustomer' in text, 'missing auto-provision'
    assert 'reserveAvailableCard' in text, 'missing commercial path'
    assert 'cardDeliverySmsBody' in text, 'missing SMS body'
    assert 'commercial_path_stub' not in text
    assert 'PLACEHOLDER' not in text
    print('OK processor', len(proc))
    try:
        test = assemble('xt')
        Path('test/services/message_parser_and_transfer_test.dart').write_bytes(test)
        ttext = test.decode('utf-8')
        assert 'auto-provisions unknown phone' in ttext
        print('OK test', len(test))
    except Exception as e:
        print('WARN test restore skipped:', e)

if __name__ == '__main__':
    main()
