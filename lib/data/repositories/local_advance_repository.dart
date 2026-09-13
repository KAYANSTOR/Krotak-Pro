part of local_repositories;

final class LocalAdvanceRepository implements AdvanceRepository {
  const LocalAdvanceRepository({required this.transactions, required this.sales});

  final LocalTransactionRepository transactions;
  final LocalSaleRepository sales;

  @override
  Future<Result<domain.Advance?>> findOpenByCustomer({required String customerId, required String currencyCode}) async {
    final all = await listByCustomer(customerId);
    if (all is Failure<List<domain.Advance>>) return Failure(all.error);
    for (final advance in (all as Success<List<domain.Advance>>).value) {
      if (advance.amount.currencyCode == currencyCode && advance.status == domain.AdvanceStatus.open) return Success(advance);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<domain.Advance>>> listByCustomer(String customerId) async {
    final txResult = await transactions.findByCustomer(customerId);
    if (txResult is Failure<List<domain.Transaction>>) return Failure(txResult.error);
    final txs = (txResult as Success<List<domain.Transaction>>).value;
    final rows = txs.where((row) => row.status == domain.TransactionStatus.completed && row.type == domain.TransactionType.advance).toList(growable: false);
    final result = <domain.Advance>[];
    for (final row in rows) {
      final sale = await sales.findById(row.id);
      if (sale is Failure<domain.Sale?>) return Failure(sale.error);
      final saleValue = (sale as Success<domain.Sale?>).value;
      if (saleValue == null) continue;
      var paid = 0;
      DateTime? settledAt;
      for (final candidate in txs) {
        if (candidate.status == domain.TransactionStatus.completed && candidate.type == domain.TransactionType.deposit && candidate.relatedTransactionId == row.id && candidate.amount.currencyCode == row.amount.currencyCode) {
          paid += candidate.amount.minorUnits;
          settledAt = candidate.createdAt;
        }
      }
      final outstandingMinor = row.amount.minorUnits - paid;
      final status = outstandingMinor <= 0 ? domain.AdvanceStatus.settled : domain.AdvanceStatus.open;
      result.add(domain.Advance(
        id: row.id,
        customerId: customerId,
        cardId: saleValue.cardId,
        amount: row.amount,
        outstanding: Money(minorUnits: outstandingMinor <= 0 ? 0 : outstandingMinor, currencyCode: row.amount.currencyCode),
        reference: row.reference ?? row.id,
        createdAt: row.createdAt,
        status: status,
        settledAt: status == domain.AdvanceStatus.settled ? settledAt : null,
      ));
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Success(result);
  }

  @override
  Future<Result<domain.Advance?>> findById(String id) async {
    final all = await transactions.listRecent(limit: 1000);
    if (all is Failure<List<domain.Transaction>>) return Failure(all.error);
    final tx = (all as Success<List<domain.Transaction>>).value.where((t) => t.id == id && t.type == domain.TransactionType.advance && t.customerId != null).firstOrNull;
    if (tx == null) return const Success(null);
    final list = await listByCustomer(tx.customerId!);
    if (list is Failure<List<domain.Advance>>) return Failure(list.error);
    for (final advance in (list as Success<List<domain.Advance>>).value) {
      if (advance.id == id) return Success(advance);
    }
    return const Success(null);
  }
}
