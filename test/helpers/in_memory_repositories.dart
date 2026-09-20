import 'package:net_app/core/result.dart';
import 'package:net_app/domain/domain.dart';

/// Shared in-memory fakes that implement the frozen repository contracts.
/// Prefer these over one-off fakes in new tests (Phase 1 contracts rule).

final class InMemoryMessageRepository implements MessageRepository {
  final Map<String, IncomingMessage> _byId = {};

  @override
  Future<Result<void>> save(IncomingMessage message) async {
    _byId[message.id] = message;
    return const Success(null);
  }

  @override
  Future<Result<IncomingMessage?>> findById(String id) async =>
      Success(_byId[id]);

  @override
  Future<Result<IncomingMessage?>> findByExternalReference(String reference) async {
    for (final m in _byId.values) {
      if (m.externalReference == reference) return Success(m);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<IncomingMessage>>> pendingProcessing() async {
    final list = _byId.values
        .where((m) =>
            m.status == MessageProcessingStatus.received ||
            m.status == MessageProcessingStatus.parsed ||
            m.status == MessageProcessingStatus.pending ||
            m.status == MessageProcessingStatus.sending ||
            m.status == MessageProcessingStatus.failed)
        .toList();
    return Success(list);
  }

  @override
  Future<Result<List<IncomingMessage>>> listByStatus(MessageProcessingStatus status) async {
    return Success(_byId.values.where((m) => m.status == status).toList());
  }

  @override
  Future<Result<List<IncomingMessage>>> listRecent({int limit = 100}) async {
    final list = _byId.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return Success(list.take(limit).toList());
  }

  @override
  Future<Result<void>> updateStatus(String id, MessageProcessingStatus status) async {
    final current = _byId[id];
    if (current == null) {
      return const Failure(AppFailure(code: 'not_found', message: 'message not found'));
    }
    _byId[id] = IncomingMessage(
      id: current.id,
      sender: current.sender,
      body: current.body,
      receivedAt: current.receivedAt,
      status: status,
      externalReference: current.externalReference,
      customerIdentifier: current.customerIdentifier,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    _byId.remove(id);
    return const Success(null);
  }
}

final class InMemoryAuditLogRepository implements AuditLogRepository {
  final List<AuditLog> logs = [];

  @override
  Future<Result<void>> append(AuditLog log) async {
    logs.add(log);
    return const Success(null);
  }

  @override
  Future<Result<List<AuditLog>>> findByEntity(String entityType, String entityId) async {
    return Success(
      logs.where((l) => l.entityType == entityType && l.entityId == entityId).toList(),
    );
  }
}

final class InMemoryUnitOfWork implements UnitOfWork {
  @override
  Future<Result<T>> run<T>(Future<Result<T>> Function() action) => action();
}

final class InMemoryCustomerRepository implements CustomerRepository {
  final Map<String, Customer> _customers = {};
  final Map<String, CustomerIdentifier> _identifiers = {};

  @override
  Future<Result<Customer?>> findById(String id) async => Success(_customers[id]);

  @override
  Future<Result<Customer?>> findByIdentifier(String value) async {
    for (final id in _identifiers.values) {
      if (id.value == value) return Success(_customers[id.customerId]);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<Customer>>> search(String query) async {
    final q = query.toLowerCase();
    return Success(
      _customers.values.where((c) => c.displayName.toLowerCase().contains(q)).toList(),
    );
  }

  @override
  Future<Result<List<CustomerIdentifier>>> listIdentifiers(String customerId) async {
    return Success(_identifiers.values.where((i) => i.customerId == customerId).toList());
  }

  @override
  Future<Result<void>> save(Customer customer) async {
    _customers[customer.id] = customer;
    return const Success(null);
  }

  @override
  Future<Result<void>> saveIdentifier(CustomerIdentifier identifier) async {
    _identifiers[identifier.id] = identifier;
    return const Success(null);
  }
}

final class InMemoryCardRepository implements CardRepository {
  final Map<String, Card> _cards = {};

  @override
  Future<Result<Card?>> findById(String id) async => Success(_cards[id]);

  @override
  Future<Result<Card?>> findBySerialNumber(String serialNumber) async {
    for (final c in _cards.values) {
      if (c.serialNumber == serialNumber) return Success(c);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<Card>>> listAll() async =>
      Success(_cards.values.toList(growable: false));

  @override
  Future<Result<Set<String>>> existingSerialsAmong(Iterable<String> serials) async {
    final set = serials.toSet();
    return Success(_cards.values.map((c) => c.serialNumber).where(set.contains).toSet());
  }

  @override
  Future<Result<Set<String>>> existingSecretsAmong(Iterable<String> secrets) async {
    final set = secrets.toSet();
    return Success(_cards.values.map((c) => c.secretCode).where(set.contains).toSet());
  }

  @override
  Future<Result<List<Card>>> findByCategory(String categoryId) async =>
      Success(_cards.values.where((c) => c.categoryId == categoryId).toList());

  @override
  Future<Result<List<Card>>> findAvailableByCategory(String categoryId) async =>
      Success(_cards.values
          .where((c) => c.categoryId == categoryId && c.status == CardStatus.available)
          .toList());

  @override
  Future<Result<Card>> reserveFirstAvailable({
    required String categoryId,
    required String reservationId,
    required DateTime reservedAt,
    required DateTime expiresAt,
  }) async {
    await expireReservations(reservedAt);
    final stock = _cards.values
        .where((c) => c.categoryId == categoryId && c.status == CardStatus.available)
        .toList();
    if (stock.isEmpty) {
      return const Failure(
        AppFailure(code: 'card_unavailable', message: 'No available card in category'),
      );
    }
    final selected = stock.first;
    final reserved = Card(
      id: selected.id,
      categoryId: selected.categoryId,
      serialNumber: selected.serialNumber,
      secretCode: selected.secretCode,
      status: CardStatus.reserved,
      reservation: CardReservation(
        reservationId: reservationId,
        reservedAt: reservedAt,
        expiresAt: expiresAt,
      ),
    );
    _cards[selected.id] = reserved;
    return Success(reserved);
  }

  @override
  Future<Result<List<Card>>> listByStatus(CardStatus status) async =>
      Success(_cards.values.where((c) => c.status == status).toList());

  @override
  Future<Result<void>> save(Card card) async {
    _cards[card.id] = card;
    return const Success(null);
  }

  @override
  Future<Result<void>> saveAll(List<Card> cards) async {
    for (final c in cards) {
      _cards[c.id] = c;
    }
    return const Success(null);
  }

  @override
  Future<Result<int>> expireReservations(DateTime now) async {
    var n = 0;
    for (final e in _cards.entries.toList()) {
      final r = e.value.reservation;
      if (r.isReserved && r.expiresAt != null && !r.expiresAt!.isAfter(now)) {
        _cards[e.key] = Card(
          id: e.value.id,
          categoryId: e.value.categoryId,
          serialNumber: e.value.serialNumber,
          secretCode: e.value.secretCode,
          status: CardStatus.available,
        );
        n++;
      }
    }
    return Success(n);
  }

  @override
  Future<Result<void>> reserve(String cardId, CardReservation reservation) async {
    final c = _cards[cardId];
    if (c == null) {
      return const Failure(AppFailure(code: 'not_found', message: 'card not found'));
    }
    _cards[cardId] = Card(
      id: c.id,
      categoryId: c.categoryId,
      serialNumber: c.serialNumber,
      secretCode: c.secretCode,
      status: CardStatus.reserved,
      reservation: reservation,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> releaseReservation(String cardId, String reservationId) async {
    final c = _cards[cardId];
    if (c == null) {
      return const Failure(AppFailure(code: 'not_found', message: 'card not found'));
    }
    _cards[cardId] = Card(
      id: c.id,
      categoryId: c.categoryId,
      serialNumber: c.serialNumber,
      secretCode: c.secretCode,
      status: CardStatus.available,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> markSold(String cardId, String saleId) async {
    final c = _cards[cardId];
    if (c == null) {
      return const Failure(AppFailure(code: 'not_found', message: 'card not found'));
    }
    _cards[cardId] = Card(
      id: c.id,
      categoryId: c.categoryId,
      serialNumber: c.serialNumber,
      secretCode: c.secretCode,
      status: CardStatus.sold,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> restoreAvailable(String cardId) async {
    final c = _cards[cardId];
    if (c == null) {
      return const Failure(AppFailure(code: 'not_found', message: 'card not found'));
    }
    _cards[cardId] = Card(
      id: c.id,
      categoryId: c.categoryId,
      serialNumber: c.serialNumber,
      secretCode: c.secretCode,
      status: CardStatus.available,
    );
    return const Success(null);
  }
}

final class InMemoryTransactionRepository implements TransactionRepository {
  final List<Transaction> _items = [];

  @override
  Future<Result<void>> append(Transaction transaction) async {
    _items.add(transaction);
    return const Success(null);
  }

  @override
  Future<Result<List<Transaction>>> findByCustomer(String customerId) async =>
      Success(_items.where((t) => t.customerId == customerId).toList());

  @override
  Future<Result<Transaction?>> findByReference(String reference) async {
    for (final t in _items) {
      if (t.reference == reference) return Success(t);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<Transaction>>> listRecent({int limit = 50}) async {
    final list = List<Transaction>.from(_items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Success(list.take(limit).toList());
  }

  @override
  Future<Result<List<Transaction>>> listCompleted({String? currencyCode}) async {
    return Success(_items.where((t) {
      if (t.status != TransactionStatus.completed) return false;
      if (currencyCode != null && t.amount.currencyCode != currencyCode) return false;
      return true;
    }).toList());
  }
}

final class InMemorySaleRepository implements SaleRepository {
  final Map<String, Sale> _sales = {};

  @override
  Future<Result<void>> save(Sale sale) async {
    _sales[sale.id] = sale;
    return const Success(null);
  }

  @override
  Future<Result<Sale?>> findById(String id) async => Success(_sales[id]);

  @override
  Future<Result<List<Sale>>> findByCustomer(String customerId) async =>
      Success(_sales.values.where((s) => s.customerId == customerId).toList());

  @override
  Future<Result<List<Sale>>> listRecent({int limit = 50}) async {
    final list = _sales.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Success(list.take(limit).toList());
  }

  @override
  Future<Result<List<Sale>>> listCompletedBetween(DateTime from, DateTime to) async {
    return Success(_sales.values.where((s) {
      if (s.status != TransactionStatus.completed) return false;
      return !s.createdAt.isBefore(from) && !s.createdAt.isAfter(to);
    }).toList());
  }
}
