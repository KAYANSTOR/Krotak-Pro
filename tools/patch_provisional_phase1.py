#!/usr/bin/env python3
from pathlib import Path

def must_replace(path, old, new, label):
    text = path.read_text()
    if old not in text:
        if new[:60] in text or label in ('skip',):
            print('skip', label)
            return
        raise SystemExit(f'missing {label} in {path}')
    path.write_text(text.replace(old, new, 1))
    print('ok', label)

root = Path('.')

c = root / 'lib/domain/entities/customer.dart'
ct = c.read_text()
if 'provisional' not in ct:
    must_replace(
        c,
        'enum CustomerStatus { active, blacklisted, merged, archived }',
        'enum CustomerStatus { active, provisional, blacklisted, merged, archived }',
        'customer.enum',
    )
else:
    print('skip customer.enum')

s = root / 'lib/domain/services/services.dart'
st = s.read_text()
if 'promoteToActive' not in st:
    old = (
        '  Future<Result<Customer>> create({\n'
        '    required String displayName,\n'
        '    required CustomerIdentifierType identifierType,\n'
        '    required String identifierValue,\n'
        '  });\n'
        '\n'
        '  Future<Result<void>> blacklist(String customerId);'
    )
    new = (
        '  Future<Result<Customer>> create({\n'
        '    required String displayName,\n'
        '    required CustomerIdentifierType identifierType,\n'
        '    required String identifierValue,\n'
        '    CustomerStatus status = CustomerStatus.active,\n'
        '  });\n'
        '\n'
        '  Future<Result<Customer>> promoteToActive(String customerId);\n'
        '\n'
        '  Future<Result<void>> blacklist(String customerId);'
    )
    must_replace(s, old, new, 'services.iface')
else:
    print('skip services.iface')

cs = root / 'lib/domain/services/local_customer_service.dart'
cst = cs.read_text()
if 'promoteToActive' not in cst:
    must_replace(
        cs,
        (
            '  Future<Result<Customer>> create({\n'
            '    required String displayName,\n'
            '    required CustomerIdentifierType identifierType,\n'
            '    required String identifierValue,\n'
            '  }) {'
        ),
        (
            '  Future<Result<Customer>> create({\n'
            '    required String displayName,\n'
            '    required CustomerIdentifierType identifierType,\n'
            '    required String identifierValue,\n'
            '    CustomerStatus status = CustomerStatus.active,\n'
            '  }) {'
        ),
        'cs.sig',
    )
    must_replace(
        cs,
        (
            '      final customer = Customer(\n'
            "        id: ids.next('customer'),\n"
            '        displayName: name,\n'
            '        status: CustomerStatus.active,\n'
            '        createdAt: now,\n'
            '        updatedAt: now,\n'
            '      );'
        ),
        (
            '      final initialStatus = status == CustomerStatus.provisional\n'
            '          ? CustomerStatus.provisional\n'
            '          : CustomerStatus.active;\n'
            '      final customer = Customer(\n'
            "        id: ids.next('customer'),\n"
            '        displayName: name,\n'
            '        status: initialStatus,\n'
            '        createdAt: now,\n'
            '        updatedAt: now,\n'
            '      );'
        ),
        'cs.body',
    )
    promote_block = (
        "        payloadJson: '{\"identifier\":\"$storedValue\"}',\n"
        '      );\n'
        '      if (audited is Failure<void>) return Failure(audited.error);\n'
        '      return Success(customer);\n'
        '    });\n'
        '  }\n'
        '\n'
        '  @override\n'
        '  Future<Result<void>> blacklist(String customerId) {'
    )
    promote_new = (
        "        payloadJson:\n"
        "            '{\"identifier\":\"$storedValue\",\"status\":\"${initialStatus.name}\"}',\n"
        '      );\n'
        '      if (audited is Failure<void>) return Failure(audited.error);\n'
        '      return Success(customer);\n'
        '    });\n'
        '  }\n'
        '\n'
        '  @override\n'
        '  Future<Result<Customer>> promoteToActive(String customerId) {\n'
        '    return unitOfWork.run(() async {\n'
        '      final found = await customers.findById(customerId);\n'
        '      if (found is Failure<Customer?>) return Failure(found.error);\n'
        '      final customer = (found as Success<Customer?>).value;\n'
        '      if (customer == null) {\n'
        '        return const Failure(\n'
        "          AppFailure(code: 'customer_not_found', message: 'الحساب غير موجود'),\n"
        '        );\n'
        '      }\n'
        '      if (customer.status == CustomerStatus.active) {\n'
        '        return Success(customer);\n'
        '      }\n'
        '      if (customer.status != CustomerStatus.provisional) {\n'
        '        return const Failure(\n'
        "          AppFailure(code: 'customer_not_promotable', message: 'لا يمكن اعتماد هذا الحساب كعميل'),\n"
        '        );\n'
        '      }\n'
        '      final updated = Customer(\n'
        '        id: customer.id,\n'
        '        displayName: customer.displayName,\n'
        '        status: CustomerStatus.active,\n'
        '        createdAt: customer.createdAt,\n'
        '        updatedAt: clock.now(),\n'
        '        mergedIntoId: customer.mergedIntoId,\n'
        '      );\n'
        '      final saved = await customers.save(updated);\n'
        '      if (saved is Failure<void>) return Failure(saved.error);\n'
        '      final audited = await _audit(\n'
        "        entityType: 'customer',\n"
        '        entityId: customer.id,\n'
        "        action: 'promoted_to_active',\n"
        '      );\n'
        '      if (audited is Failure<void>) return Failure(audited.error);\n'
        '      return Success(updated);\n'
        '    });\n'
        '  }\n'
        '\n'
        '  @override\n'
        '  Future<Result<void>> blacklist(String customerId) {'
    )
    must_replace(cs, promote_block, promote_new, 'cs.promote')
else:
    print('skip cs')

r = root / 'lib/domain/services/local_customer_identity_resolver.dart'
rt = r.read_text()
if 'CustomerStatus.provisional' not in rt:
    must_replace(
        r,
        (
            '    if (customer.status != CustomerStatus.active) {\n'
            '      return Success(\n'
            '        CustomerIdentityResolution.unresolved(\n'
            "          reasonCode: 'customer_not_active',\n"
            "          reasonMessage: 'Customer status is ${customer.status.name}',\n"
            '        ),\n'
            '      );\n'
            '    }'
        ),
        (
            '    if (customer.status != CustomerStatus.active &&\n'
            '        customer.status != CustomerStatus.provisional) {\n'
            '      return Success(\n'
            '        CustomerIdentityResolution.unresolved(\n'
            "          reasonCode: 'customer_not_active',\n"
            "          reasonMessage: 'Customer status is ${customer.status.name}',\n"
            '        ),\n'
            '      );\n'
            '    }'
        ),
        'resolver',
    )
else:
    print('skip resolver')

p = root / 'lib/domain/services/local_transfer_processor.dart'
pt = p.read_text()
if 'status: CustomerStatus.provisional' not in pt:
    must_replace(
        p,
        (
            '    final created = await service.create(\n'
            '      displayName: phone,\n'
            '      identifierType: CustomerIdentifierType.phoneNumber,\n'
            '      identifierValue: phone,\n'
            '    );'
        ),
        (
            '    final created = await service.create(\n'
            '      displayName: phone,\n'
            '      identifierType: CustomerIdentifierType.phoneNumber,\n'
            '      identifierValue: phone,\n'
            '      status: CustomerStatus.provisional,\n'
            '    );'
        ),
        'processor.create',
    )
else:
    print('skip processor.create')
if "action: 'customer_auto_provisioned'" in pt:
    must_replace(
        p,
        "action: 'customer_auto_provisioned',",
        "action: 'ledger_account_auto_provisioned',",
        'processor.audit',
    )
else:
    print('skip processor.audit or already renamed')

print('PHASE1_DOMAIN_OK')
