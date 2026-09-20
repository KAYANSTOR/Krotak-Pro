#!/usr/bin/env python3
from pathlib import Path

sale_path = Path("lib/domain/services/local_sale_service.dart")
sale = sale_path.read_text()
old = (
    "      if (customer.status != CustomerStatus.active) {\n"
    "        return const Failure(\n"
    "          AppFailure(\n"
    "            code: 'customer_not_sellable',\n"
    "            message: 'Customer is not allowed to buy',\n"
    "          ),\n"
    "        );\n"
    "      }"
)
new = (
    "      if (customer.status != CustomerStatus.active &&\n"
    "          customer.status != CustomerStatus.provisional) {\n"
    "        return const Failure(\n"
    "          AppFailure(\n"
    "            code: 'customer_not_sellable',\n"
    "            message: 'Customer is not allowed to buy',\n"
    "          ),\n"
    "        );\n"
    "      }"
)
c = sale.count(old)
print("sale matches", c)
if c == 2:
    sale_path.write_text(sale.replace(old, new))
    print("sale provisional OK")
elif "CustomerStatus.provisional" in sale:
    print("sale already provisional")
else:
    raise SystemExit("sale patch failed")

ltp_path = Path("lib/domain/services/local_transfer_processor.dart")
ltp = ltp_path.read_text()
ltp = ltp.replace(
    "final class LocalTransferProcessor implements TransferProcessor {\n  const LocalTransferProcessor({",
    "final class LocalTransferProcessor implements TransferProcessor {\n  LocalTransferProcessor({",
    1,
)
if "_categoryCache" not in ltp:
    old_f = "  final Duration reservationTtl;\n\n  LocalCustomerIdentityResolver get _resolver =>"
    new_f = (
        "  final Duration reservationTtl;\n\n"
        "  List<CardCategory>? _categoryCache;\n"
        "  DateTime? _categoryCacheAt;\n"
        "  static const Duration _categoryCacheTtl = Duration(seconds: 45);\n\n"
        "  LocalCustomerIdentityResolver get _resolver =>"
    )
    assert old_f in ltp, "fields marker"
    ltp = ltp.replace(old_f, new_f, 1)

if "_matchActiveCategory" not in ltp:
    old_m = (
        "    final allCategories = await categoriesRepo.listAll();\n"
        "    if (allCategories is Failure<List<CardCategory>>) {\n"
        "      return Failure<Transaction>(allCategories.error);\n"
        "    }\n"
        "    final matches = (allCategories as Success<List<CardCategory>>)\n"
        "        .value\n"
        "        .where(\n"
        "          (category) =>\n"
        "              category.isActive &&\n"
        "              category.faceValue.currencyCode == effectiveAmount.currencyCode &&\n"
        "              category.faceValue.minorUnits == effectiveAmount.minorUnits,\n"
        "        )\n"
        "        .toList(growable: false);\n"
        "    if (matches.isEmpty) {"
    )
    new_m = (
        "    final matchResult = await _matchActiveCategory(effectiveAmount);\n"
        "    if (matchResult is Failure<List<CardCategory>>) {\n"
        "      return Failure<Transaction>(matchResult.error);\n"
        "    }\n"
        "    final matches = (matchResult as Success<List<CardCategory>>).value;\n"
        "    if (matches.isEmpty) {"
    )
    assert old_m in ltp, "match marker"
    ltp = ltp.replace(old_m, new_m, 1)

if "Future<Result<List<CardCategory>>> _matchActiveCategory" not in ltp:
    helper = (
        "\n"
        "  Future<Result<List<CardCategory>>> _matchActiveCategory(Money amount) async {\n"
        "    final categoriesRepo = categories!;\n"
        "    final now = clock.now();\n"
        "    final stale = _categoryCache == null ||\n"
        "        _categoryCacheAt == null ||\n"
        "        now.difference(_categoryCacheAt!) > _categoryCacheTtl;\n"
        "    if (stale) {\n"
        "      final all = await categoriesRepo.listAll();\n"
        "      if (all is Failure<List<CardCategory>>) {\n"
        "        return Failure(all.error);\n"
        "      }\n"
        "      _categoryCache = (all as Success<List<CardCategory>>).value;\n"
        "      _categoryCacheAt = now;\n"
        "    }\n"
        "    final matches = _categoryCache!\n"
        "        .where(\n"
        "          (category) =>\n"
        "              category.isActive &&\n"
        "              category.faceValue.currencyCode == amount.currencyCode &&\n"
        "              category.faceValue.minorUnits == amount.minorUnits,\n"
        "        )\n"
        "        .toList(growable: false);\n"
        "    return Success(matches);\n"
        "  }\n"
        "\n"
        "  bool _canAutoProvision(ParsedTransfer transfer) {"
    )
    old_can = "  bool _canAutoProvision(ParsedTransfer transfer) {"
    assert old_can in ltp, "canAuto marker"
    ltp = ltp.replace(old_can, helper, 1)

if "import '../entities/money.dart';" not in ltp:
    ltp = ltp.replace(
        "import '../entities/message.dart';",
        "import '../entities/message.dart';\nimport '../entities/money.dart';",
        1,
    )
ltp_path.write_text(ltp)
print("processor cache OK")

Path("docs/phase-engine-hotpath.md").write_text(
    "# Phase engine-hotpath (slice 1)\n\n"
    "- Provisional sellable (critical for phase-1 ledger accounts)\n"
    "- Category face-value cache 45s TTL on LocalTransferProcessor\n"
    "\nNext: atomic reserveFirstAvailable + inventory hot path.\n"
)
assert "_matchActiveCategory" in ltp_path.read_text()
print("HOTPATH_SLICE1_OK")
