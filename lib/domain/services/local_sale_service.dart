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
import 'manual_sale_runner.dart';
import 'services.dart';

final class LocalSaleService implements SaleService, ReservedSaleService {
  const LocalSaleService({
    required this.customers,
    required this.categories,
    required this.cards,
    required this.sales,
    required this.transactions,
    required this.balances,
    required this.inventory,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
    this.messageSender,
    this.settings,
    this.reservationTtl = const Duration(minutes: 5),
  });

  final CustomerRepository customers;
  final CardCategoryRepository categories;
  final CardRepository cards;