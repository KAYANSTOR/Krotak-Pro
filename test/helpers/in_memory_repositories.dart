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
  Future<Result<List<CustomerPhoneSuggestion>>> suggestPhonesByPrefix(
    String prefix, {
    int limit = 8,
  }) async {
    final digits = prefix.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '');
    final latin = digits
        .replaceAllMapped(RegExp(r'[٠-٩]'), (m) {
          return '${m[0]!.codeUnitAt(0) - 0x0660}';
        })
        .replaceAllMapped(RegExp(r'[۰-۹]'), (m) {
          return '${m[0]!.codeUnitAt(0) - 0x06f0}';
        });
    if (latin.isEmpty || limit <= 0) {
      return const Success(<CustomerPhoneSuggestion>[]);
    }
    final allowed = {CustomerStatus.active, CustomerStatus.provisional};
    final matches = <CustomerPhoneSuggestion>[];
    for (final ident in _identifiers.values) {
      if (ident.type != CustomerIdentifierType.phoneNumber) continue;
      if (!ident.value.startsWith(latin)) continue;
      final customer = _customers[ident.customerId];
      if (customer == null || !allowed.contains(customer.status)) continue;
      matches.add(
        CustomerPhoneSuggestion(
          customerId: customer.id,
          phone: ident.value,
          displayName: customer.displayName,
          status: customer.status,
          updatedAt: customer.updatedAt,
        ),
      );
    }
    matches.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Success(matches.take(limit).toList(growable: false));
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
