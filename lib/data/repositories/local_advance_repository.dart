part of local_repositories;

final class LocalAdvanceRepository implements AdvanceRepository {
  const LocalAdvanceRepository({required this.transactions, required this.sales});

  final LocalTransactionRepository transactions;
  final LocalSaleRepository sales;

  @override
  Future<Result<Advance?>> findOpenByCustomer({
    required String customerId,
    required String currencyCode,
  }) async {
    final all = await listByCustomer(customerId);
    if (all is Failure<List<Advance>>) return Failure(all.error);
    for (final advance in (all as Success<List<Advance>>).value) {
      if (advance.amount.currencyCode == currencyCode &&
          advance.status == AdvanceStatus.open) {
        return Success(advance);
      }
    }
    return const Success(null);
  }

  @override
  Future<Result<List<Advance>>> listByCustomer(String customerId) async {
    final txResult = await transactions.findByCustomer(customerId);
    if (txResult is Failure<List<Transaction>>) return Failure(txResult.error);
    final rows = (txResult as Success<List<Transaction>>).value
        .where((row) => row.status == TransactionStatus.completed && row.type == TransactionType.advance)
        .toList(growable: false);
    final result = <Advance>[];
    for (final row in rows) {
      final sale = await sales.findById(row.id);
      if (sale is Failure<Sale?>) return Failure(sale.error);
      final saleValue = (sale as Success<Sale?>).value;
      if (saleValue == null) continue;

      final linked = (await transactions.findByCustomer(customerId));
      if (linked is Failure<List<Transaction>>) return Failure(linked.error);
      final payments = (linked as Success<List<Transaction>>).value.where(
        (t) => t.status == TransactionStatus.completed &&
            t.type == TransactionType.deposit &&
            t.relatedTransactionId == row.id,
      );
      var paid = 0;
      DateTime? settledAt;
      for (final payment in payments) {
        paid += payment.amount.minorUnits;
        settledAt = payment.createdAt;
      }
      final outstandingMinor = row.amount.minorUnits - paid;
      final status = outstandingMinor <= 0 ? AdvanceStatus.settled : AdvanceStatus.open;
      result.add(
        Advance(
          id: row.id,
          customerId: customerId,
          cardId: saleValue.cardId,
          amount: row.amount,
          outstanding: Money(minorUnits: outstandingMinor.clamp(0, row.amount.minorUnits), currencyCode: row.amount.currencyCode),
          reference: row.reference ?? row.id,
          createdAt: row.createdAt,
          status: status,
          settledAt: status == AdvanceStatus.settled ? settledAt : null,
        ),
      );
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Success(result);
  }

  @override
  Future<Result<Advance?>> findById(String id) async {
    final tx = await transactions.findByReference('salafni:$id');
    if (tx is Failure<Transaction?>) return Failure(tx.error);
    final value = (tx as Success<Transaction?>).value;
    if (value == null || value.type != TransactionType.advance || value.customerId == null) {
      return const Success(null);
    }
    final list = await listByCustomer(value.customerId!);
    if (list is Failure<List<Advance>>) return Failure(list.error);
    for (final advance in (list as Success<List<Advance>>).value) {
      if (advance.id == value.id) return Success(advance);
    }
    return const Success(null);
  }
}
