import '../../core/result.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/transaction.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';

final class SoldCardRecord {
  const SoldCardRecord({
    required this.card,
    required this.sale,
    this.categoryName,
    this.customerName,
    this.customerPhone,
    this.isPointOfSale = false,
  });

  final Card card;
  final Sale sale;
  final String? categoryName;
  final String? customerName;
  final String? customerPhone;
  final bool isPointOfSale;
}

final class SoldCardFilter {
  const SoldCardFilter({
    this.categoryId,
    this.customerId,
    this.serialQuery,
    this.from,
    this.to,
    this.saleStatus,
  });

  final String? categoryId;
  final String? customerId;
  final String? serialQuery;
  final DateTime? from;
  final DateTime? to;
  final TransactionStatus? saleStatus;
}

/// يجمع الكروت المباعة مع عملية البيع والحساب دون كسر السجل المالي.
final class LocalSoldCardQueryService {
  const LocalSoldCardQueryService({
    required this.cards,
    required this.sales,
    required this.customers,
    required this.categories,
    this.pointsOfSale,
  });

  final CardRepository cards;
  final SaleRepository sales;
  final CustomerRepository customers;
  final CardCategoryRepository categories;
  final PointOfSaleRepository? pointsOfSale;

  Future<Result<List<SoldCardRecord>>> list(SoldCardFilter filter) async {
    final salesResult = await sales.listRecent(limit: 5000);
    if (salesResult is Failure<List<Sale>>) return Failure(salesResult.error);
    final allSales = (salesResult as Success<List<Sale>>).value;

    final catsResult = await categories.listAll();
    if (catsResult is Failure<List<CardCategory>>) {
      return Failure(catsResult.error);
    }
    final catNames = {
      for (final c in (catsResult as Success<List<CardCategory>>).value) c.id: c.name,
    };

    final posIds = <String>{};
    if (pointsOfSale != null) {
      final posResult = await pointsOfSale!.listAll();
      if (posResult is Success<List<PointOfSale>>) {
        posIds.addAll(posResult.value.map((e) => e.id));
      }
    }

    final serialQ = filter.serialQuery?.trim() ?? '';
    final out = <SoldCardRecord>[];
    for (final sale in allSales) {
      if (filter.saleStatus != null && sale.status != filter.saleStatus) continue;
      if (filter.customerId != null && sale.customerId != filter.customerId) {
        continue;
      }
      if (filter.from != null && sale.createdAt.isBefore(filter.from!)) continue;
      if (filter.to != null && sale.createdAt.isAfter(filter.to!)) continue;

      final cardResult = await cards.findById(sale.cardId);
      if (cardResult is Failure<Card?>) return Failure(cardResult.error);
      final card = (cardResult as Success<Card?>).value;
      if (card == null) continue;
      if (filter.categoryId != null && card.categoryId != filter.categoryId) {
        continue;
      }
      if (serialQ.isNotEmpty &&
          !card.serialNumber.contains(serialQ) &&
          !card.id.contains(serialQ)) {
        continue;
      }

      String? name;
      String? phone;
      final customerResult = await customers.findById(sale.customerId);
      if (customerResult is Success<Customer?> && customerResult.value != null) {
        name = customerResult.value!.displayName;
      }
      final idsResult = await customers.listIdentifiers(sale.customerId);
      if (idsResult is Success<List<CustomerIdentifier>>) {
        final phones = idsResult.value
            .where((e) => e.type == CustomerIdentifierType.phoneNumber)
            .map((e) => e.value);
        if (phones.isNotEmpty) phone = phones.first;
      }

      out.add(
        SoldCardRecord(
          card: card,
          sale: sale,
          categoryName: catNames[card.categoryId],
          customerName: name,
          customerPhone: phone,
          isPointOfSale: posIds.contains(sale.customerId),
        ),
      );
    }
    out.sort((a, b) => b.sale.createdAt.compareTo(a.sale.createdAt));
    return Success(out);
  }

  static String toCsv(List<SoldCardRecord> rows) {
    final buf = StringBuffer(
      'serial,category,customer,phone,amount,currency,sale_status,sold_at,card_status,sale_id\n',
    );
    for (final row in rows) {
      String esc(String? v) {
        final s = v ?? '';
        if (s.contains(',') || s.contains('"') || s.contains('\n')) {
          return '"${s.replaceAll('"', '""')}"';
        }
        return s;
      }

      buf.writeln(
        [
          esc(row.card.serialNumber),
          esc(row.categoryName),
          esc(row.customerName),
          esc(row.customerPhone),
          row.sale.amount.minorUnits.toString(),
          esc(row.sale.amount.currencyCode),
          row.sale.status.name,
          row.sale.createdAt.toIso8601String(),
          row.card.status.name,
          esc(row.sale.id),
        ].join(','),
      );
    }
    return buf.toString();
  }

  static String toReportText(List<SoldCardRecord> rows) {
    final lines = <String>[
      'كروتك برو — تصدير الكروت المباعة',
      'العدد: ${rows.length}',
      '---',
      ...rows.map((row) {
        return '${row.card.serialNumber} | ${row.categoryName ?? row.card.categoryId} | '
            '${row.customerName ?? row.sale.customerId} | '
            '${row.sale.amount.minorUnits} ${row.sale.amount.currencyCode} | '
            '${row.sale.createdAt.toIso8601String()}';
      }),
    ];
    return lines.join('\n');
  }
}
