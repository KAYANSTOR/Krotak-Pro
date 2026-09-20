#!/usr/bin/env python3
import base64, gzip, pathlib
root = pathlib.Path('.')

def restore(prefix, dest, n):
    parts = [root / f'tools/hotpath/{prefix}_{i}.b64' for i in range(n)]
    missing = [str(p) for p in parts if not p.exists()]
    if missing:
        raise SystemExit(f'missing chunks: {missing}')
    raw = ''.join(p.read_text().strip() for p in parts)
    data = gzip.decompress(base64.b64decode(raw))
    out = root / dest
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print('wrote', dest, len(data))

restore('ltp', 'lib/domain/services/local_transfer_processor.dart', 3)
restore('sale', 'lib/domain/services/local_sale_service.dart', 2)
restore('card', 'lib/data/repositories/local_card_repository.dart', 1)
restore('repos', 'lib/domain/repositories/repositories.dart', 1)
restore('inv', 'lib/domain/services/local_card_inventory_service.dart', 1)
restore('inmem', 'test/helpers/in_memory_repositories.dart', 2)
restore('docs', 'docs/phase-engine-hotpath.md', 1)

checks = {
    'lib/domain/services/local_transfer_processor.dart': ['_matchActiveCategory', '_categoryCache', 'reserveAvailableCard'],
    'lib/domain/services/local_sale_service.dart': ['CustomerStatus.provisional'],
    'lib/data/repositories/local_card_repository.dart': ['reserveFirstAvailable'],
    'lib/domain/repositories/repositories.dart': ['reserveFirstAvailable'],
    'lib/domain/services/local_card_inventory_service.dart': ['reserveFirstAvailable'],
    'test/helpers/in_memory_repositories.dart': ['reserveFirstAvailable'],
}
for path, needles in checks.items():
    text = (root / path).read_text()
    for n in needles:
        assert n in text, f'{path} missing {n}'
print('HOTPATH_OK')
