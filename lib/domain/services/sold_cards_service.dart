import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';

/// صف كرت مباع مع بيانات البيع والعميل (من الدفتر الحقيقي).
final class SoldCardRow {
  const SoldCardRow({
    required this.card,
    required this.sale,
    required this.categoryName,
    required this.faceValue,
    this.customerName,
    this.customerPhone,
  });

  final Card card;
  final Sale sale;
  final String categoryName;
  final Money faceValue;
  final String? customerName;
  final String? customerPhone;
}

/// فلاتر استعلام الكروت المباعة (خطة §8).
final class SoldCardsFilter {
  const SoldCardsFilter({
    this.from,
    this.to,
    this.categoryId,
    this.customerId,
    this.serialQuery,
  });

  final DateTime? from;
  final DateTime? to;
  final String? categoryId;
  final String? customerId;
  final String? serialQuery;
}

/// استعلام + تصدير + سياسة حذف آمنة للكروت المباعة.
final class SoldCardsService {
  const SoldCardsService({
    required this.cards,
    required this.sales,
    required this.customers,
    required this.categories,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final CardRepository cards;
  final SaleRepository sales;
  final CustomerRepository customers;
  final CardCategoryRepository categories;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  /// يجلب الكروت ذات الحالة sold ويربطها بأحدث عملية بيع مكتملة إن وُجدت.
  Future<Result<List<SoldCardRow>>> query(SoldCardsFilter filter) async {
    final soldResult = await cards.listByStatus(CardStatus.sold);
    if (soldResult is Failure<List<Card>>) return Failure(soldResult.error);
    var soldCards = (soldResult as Success<List<Card>>).value;

    final catFilter = filter.categoryId?.trim();
    if (catFilter != null && catFilter.isNotEmpty) {
      soldCards = soldCards.where((c) => c.categoryId == catFilter).toList();
    }

    final serialQ = filter.serialQuery?.trim().toLowerCase() ?? '';
    if (serialQ.isNotEmpty) {
      soldCards = soldCards
          .where((c) => c.serialNumber.toLowerCase().contains(serialQ))
          .toList();
    }

    if (soldCards.isEmpty) {
      return const Success(<SoldCardRow>[]);
    }

    // Load recent sales window for matching.
    final to = filter.to ?? clock.now().add(const Duration(days: 1));
    final from = filter.from ?? DateTime.utc(2000);
    final salesR = await sales.listCompletedBetween(from, to);
    if (salesR is Failure<List<Sale>>) return Failure(salesR.error);
    var saleList = (salesR as Success<List<Sale>>).value
        .where((s) => s.status == TransactionStatus.completed)
        .toList();

    final customerFilter = filter.customerId?.trim();
    if (customerFilter != null && customerFilter.isNotEmpty) {
      saleList = saleList.where((s) => s.customerId == customerFilter).toList();
    }

    // Latest sale per cardId.
    final byCard = <String, Sale>{};
    for (final s in saleList) {
      final prev = byCard[s.cardId];
      if (prev == null || s.createdAt.isAfter(prev.createdAt)) {
        byCard[s.cardId] = s;
      }
    }

    final catsR = await categories.listAll();
    final catMap = <String, CardCategory>{};
    if (catsR is Success<List<CardCategory>>) {
      for (final c in catsR.value) {
        catMap[c.id] = c;
      }
    }

    final rows = <SoldCardRow>[];
    for (final card in soldCards) {
      final sale = byCard[card.id];
      if (sale == null) {
        // Sold in inventory but no sale in date window — still list when no
        // date/customer constraint requires a sale match.
        if (filter.from != null ||
            filter.to != null ||
            (customerFilter != null && customerFilter.isNotEmpty)) {
          continue;
        }
        final cat = catMap[card.categoryId];
        rows.add(
          SoldCardRow(
            card: card,
            sale: Sale(
              id: 'unknown',
              customerId: '',
              cardId: card.id,
              amount: cat?.faceValue ??
                  const Money(minorUnits: 0, currencyCode: 'YER'),
              status: TransactionStatus.completed,
              createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            ),
            categoryName: cat?.name ?? card.categoryId,
            faceValue: cat?.faceValue ??
                const Money(minorUnits: 0, currencyCode: 'YER'),
          ),
        );
        continue;
      }

      String? name;
      String? phone;
      if (sale.customerId.isNotEmpty) {
        final cust = await customers.findById(sale.customerId);
        if (cust is Success<Customer?> && cust.value != null) {
          name = cust.value!.displayName;
        }
        final idsR = await customers.listIdentifiers(sale.customerId);
        if (idsR is Success<List<CustomerIdentifier>>) {
          for (final id in idsR.value) {
            if (id.type == CustomerIdentifierType.phoneNumber) {
              phone = id.value;
              if (id.isPrimary) break;
            }
          }
        }
      }

      final cat = catMap[card.categoryId];
      rows.add(
        SoldCardRow(
          card: card,
          sale: sale,
          categoryName: cat?.name ?? card.categoryId,
          faceValue: cat?.faceValue ?? sale.amount,
          customerName: name,
          customerPhone: phone,
        ),
      );
    }

    rows.sort((a, b) => b.sale.createdAt.compareTo(a.sale.createdAt));
    return Success(rows);
  }

  /// نص CSV جاهز للمشاركة/التصدير.
  String exportCsv(List<SoldCardRow> rows) {
    final buf = StringBuffer();
    buf.writeln('serial,category,face_value,customer,phone,sale_id,sold_at,amount');
    for (final r in rows) {
      final soldAt = r.sale.id == 'unknown'
          ? ''
          : r.sale.createdAt.toIso8601String();
      buf.writeln(
        [
          _csv(r.card.serialNumber),
          _csv(r.categoryName),
          (r.faceValue.minorUnits / 100).toStringAsFixed(2),
          _csv(r.customerName ?? ''),
          _csv(r.customerPhone ?? ''),
          _csv(r.sale.id == 'unknown' ? '' : r.sale.id),
          soldAt,
          (r.sale.amount.minorUnits / 100).toStringAsFixed(2),
        ].join(','),
      );
    }
    return buf.toString();
  }

  static String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
