#!/usr/bin/env python3
from pathlib import Path

def must_replace(path, old, new, label):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if "reserveFirstAvailable" in text:
            print("skip already", path, label)
            return
        raise SystemExit("MISSING marker in %s: %s" % (path, label))
    c = text.count(old)
    if c != 1:
        raise SystemExit("Expected 1 occurrence of %s in %s, found %d" % (label, path, c))
    p.write_text(text.replace(old, new, 1))
    print("patched", path, label)

# 1) interface
must_replace(
    "lib/domain/repositories/repositories.dart",
    "  Future<Result<List<Card>>> findAvailableByCategory(String categoryId);\n  Future<Result<List<Card>>> listByStatus(CardStatus status);",
    "  Future<Result<List<Card>>> findAvailableByCategory(String categoryId);\n"
    "  Future<Result<Card>> reserveFirstAvailable({\n"
    "    required String categoryId,\n"
    "    required String reservationId,\n"
    "    required DateTime reservedAt,\n"
    "    required DateTime expiresAt,\n"
    "  });\n"
    "  Future<Result<List<Card>>> listByStatus(CardStatus status);",
    "repos.api",
)

# 2) LocalCardRepository
ANCHOR = (
    "  @override\n"
    "  Future<Result<List<domain.Card>>> findAvailableByCategory(String categoryId) async {\n"
    "    try {\n"
    "      final rows = await (database.select(database.cards)\n"
    "            ..where(\n"
    "              (table) =>\n"
    "                  table.categoryId.equals(categoryId) &\n"
    "                  table.status.equals(domain.CardStatus.available.name),\n"
    "            )\n"
    "            ..orderBy([(table) => OrderingTerm(expression: table.serialNumber)]))\n"
    "          .get();\n"
    "      return Success(rows.map(_toCard).toList(growable: false));\n"
    "    } catch (error) {\n"
    "      return Failure(_failure('card_available_find_failed', error));\n"
    "    }\n"
    "  }\n"
)
METHOD = (
    "\n"
    "  @override\n"
    "  Future<Result<domain.Card>> reserveFirstAvailable({\n"
    "    required String categoryId,\n"
    "    required String reservationId,\n"
    "    required DateTime reservedAt,\n"
    "    required DateTime expiresAt,\n"
    "  }) async {\n"
    "    try {\n"
    "      await (database.update(database.cards)\n"
    "            ..where(\n"
    "              (table) =>\n"
    "                  table.categoryId.equals(categoryId) &\n"
    "                  table.status.equals(domain.CardStatus.reserved.name) &\n"
    "                  table.reservationExpiresAt.isNotNull() &\n"
    "                  table.reservationExpiresAt.isSmallerOrEqualValue(reservedAt),\n"
    "            ))\n"
    "          .write(\n"
    "        const CardsCompanion(\n"
    "          status: Value('available'),\n"
    "          reservationId: Value(null),\n"
    "          reservedAt: Value(null),\n"
    "          reservationExpiresAt: Value(null),\n"
    "        ),\n"
    "      );\n"
    "\n"
    "      final candidate = await (database.select(database.cards)\n"
    "            ..where(\n"
    "              (table) =>\n"
    "                  table.categoryId.equals(categoryId) &\n"
    "                  table.status.equals(domain.CardStatus.available.name),\n"
    "            )\n"
    "            ..orderBy([(table) => OrderingTerm(expression: table.serialNumber)])\n"
    "            ..limit(1))\n"
    "          .getSingleOrNull();\n"
    "      if (candidate == null) {\n"
    "        return const Failure(\n"
    "          AppFailure(code: 'card_unavailable', message: 'No available card in category'),\n"
    "        );\n"
    "      }\n"
    "\n"
    "      final changed = await (database.update(database.cards)\n"
    "            ..where(\n"
    "              (table) =>\n"
    "                  table.id.equals(candidate.id) &\n"
    "                  table.status.equals(domain.CardStatus.available.name),\n"
    "            ))\n"
    "          .write(\n"
    "        CardsCompanion(\n"
    "          status: const Value('reserved'),\n"
    "          reservationId: Value(reservationId),\n"
    "          reservedAt: Value(reservedAt),\n"
    "          reservationExpiresAt: Value(expiresAt),\n"
    "        ),\n"
    "      );\n"
    "      if (changed != 1) {\n"
    "        return const Failure(\n"
    "          AppFailure(code: 'card_unavailable', message: 'No available card in category'),\n"
    "        );\n"
    "      }\n"
    "\n"
    "      return Success(\n"
    "        domain.Card(\n"
    "          id: candidate.id,\n"
    "          categoryId: candidate.categoryId,\n"
    "          serialNumber: candidate.serialNumber,\n"
    "          secretCode: candidate.secretCode,\n"
    "          status: domain.CardStatus.reserved,\n"
    "          reservation: domain.CardReservation(\n"
    "            reservationId: reservationId,\n"
    "            reservedAt: reservedAt,\n"
    "            expiresAt: expiresAt,\n"
    "          ),\n"
    "        ),\n"
    "      );\n"
    "    } catch (error) {\n"
    "      return Failure(_failure('card_reserve_first_failed', error));\n"
    "    }\n"
    "  }\n"
)
must_replace("lib/data/repositories/local_card_repository.dart", ANCHOR, ANCHOR + METHOD, "card.atomic")

# 3) inventory: inject atomic prefer at start of unitOfWork.run body
inv_path = Path("lib/domain/services/local_card_inventory_service.dart")
inv = inv_path.read_text()
if "reserveFirstAvailable" not in inv:
    old_body = (
        "    return unitOfWork.run(() async {\n"
        "      final foundCategory = await categories.findById(categoryId);\n"
    )
    new_body = (
        "    return unitOfWork.run(() async {\n"
        "      final atomic = await cards.reserveFirstAvailable(\n"
        "        categoryId: categoryId,\n"
        "        reservationId: reservationId,\n"
        "        reservedAt: now,\n"
        "        expiresAt: expiresAt,\n"
        "      );\n"
        "      if (atomic is Success<Card>) return atomic;\n"
        "      if (atomic is Failure<Card> &&\n"
        "          atomic.error.code != 'card_unavailable' &&\n"
        "          atomic.error.code != 'not_implemented') {\n"
        "        return atomic;\n"
        "      }\n"
        "\n"
        "      final foundCategory = await categories.findById(categoryId);\n"
    )
    if old_body not in inv:
        raise SystemExit("inventory marker missing")
    inv_path.write_text(inv.replace(old_body, new_body, 1))
    print("inventory atomic prefer OK")
else:
    print("inventory skip")

# 4) inmem
inmem_path = Path("test/helpers/in_memory_repositories.dart")
inmem = inmem_path.read_text()
old_av = (
    "  @override\n"
    "  Future<Result<List<Card>>> findAvailableByCategory(String categoryId) async =>\n"
    "      Success(_cards.values\n"
    "          .where((c) => c.categoryId == categoryId && c.status == CardStatus.available)\n"
    "          .toList());\n"
)
add = old_av + (
    "\n"
    "  @override\n"
    "  Future<Result<Card>> reserveFirstAvailable({\n"
    "    required String categoryId,\n"
    "    required String reservationId,\n"
    "    required DateTime reservedAt,\n"
    "    required DateTime expiresAt,\n"
    "  }) async {\n"
    "    await expireReservations(reservedAt);\n"
    "    final stock = _cards.values\n"
    "        .where((c) => c.categoryId == categoryId && c.status == CardStatus.available)\n"
    "        .toList();\n"
    "    if (stock.isEmpty) {\n"
    "      return const Failure(\n"
    "        AppFailure(code: 'card_unavailable', message: 'No available card in category'),\n"
    "      );\n"
    "    }\n"
    "    final selected = stock.first;\n"
    "    final reserved = Card(\n"
    "      id: selected.id,\n"
    "      categoryId: selected.categoryId,\n"
    "      serialNumber: selected.serialNumber,\n"
    "      secretCode: selected.secretCode,\n"
    "      status: CardStatus.reserved,\n"
    "      reservation: CardReservation(\n"
    "        reservationId: reservationId,\n"
    "        reservedAt: reservedAt,\n"
    "        expiresAt: expiresAt,\n"
    "      ),\n"
    "    );\n"
    "    _cards[selected.id] = reserved;\n"
    "    return Success(reserved);\n"
    "  }\n"
)
if "reserveFirstAvailable" not in inmem:
    if old_av not in inmem:
        raise SystemExit("inmem marker missing")
    inmem_path.write_text(inmem.replace(old_av, add, 1))
    print("inmem ok")
else:
    print("inmem skip")

Path("docs/phase-engine-hotpath.md").write_text(
    "# Phase engine-hotpath\n\n"
    "## Slice 1\n"
    "- Provisional sellable + category face-value cache 45s TTL\n\n"
    "## Slice 2\n"
    "- CardRepository.reserveFirstAvailable (category expire + LIMIT 1 + conditional UPDATE)\n"
    "- Inventory prefers atomic; legacy fallback retained\n"
    "- InMemoryCardRepository implements atomic reserve\n\n"
    "Guarantees: sale-op idempotency, provisional ledger, SMS after commit, worker retry.\n"
)

for path, needles in [
    ("lib/domain/repositories/repositories.dart", ["reserveFirstAvailable"]),
    ("lib/data/repositories/local_card_repository.dart", ["reserveFirstAvailable", "limit(1)"]),
    ("lib/domain/services/local_card_inventory_service.dart", ["reserveFirstAvailable"]),
    ("test/helpers/in_memory_repositories.dart", ["reserveFirstAvailable"]),
]:
    text = Path(path).read_text()
    for n in needles:
        assert n in text, "%s missing %s" % (path, n)
print("HOTPATH_SLICE2_OK")
