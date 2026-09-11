import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'services.dart';

final class LocalCustomerService implements CustomerService {
  const LocalCustomerService({
    required this.customers,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final CustomerRepository customers;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  @override
  Future<Result<Customer>> create({
    required String displayName,
    required CustomerIdentifierType identifierType,
    required String identifierValue,
  }) {
    final name = displayName.trim();
    final value = identifierValue.trim();
    if (name.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_display_name', message: 'Display name is required'),
        ),
      );
    }
    if (value.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_identifier', message: 'Identifier is required'),
        ),
      );
    }

    return unitOfWork.run(() async {
      final existing = await customers.findByIdentifier(value);
      if (existing is Failure<Customer?>) return Failure(existing.error);
      if ((existing as Success<Customer?>).value != null) {
        return const Failure(
          AppFailure(code: 'duplicate_identifier', message: 'Identifier already exists'),
        );
      }

      final now = clock.now();
      final customer = Customer(
        id: ids.next('customer'),
        displayName: name,
        status: CustomerStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final saved = await customers.save(customer);
      if (saved is Failure<void>) return Failure(saved.error);

      final identifier = CustomerIdentifier(
        id: ids.next('identifier'),
        customerId: customer.id,
        type: identifierType,
        value: value,
        isPrimary: true,
      );
      final savedIdentifier = await customers.saveIdentifier(identifier);
      if (savedIdentifier is Failure<void>) return Failure(savedIdentifier.error);

      final audited = await _audit(
        entityType: 'customer',
        entityId: customer.id,
        action: 'created',
        payloadJson: '{"identifier":"$value"}',
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(customer);
    });
  }

  @override
  Future<Result<void>> blacklist(String customerId) {
    return unitOfWork.run(() async {
      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (customer.status == CustomerStatus.merged) {
        return const Failure(
          AppFailure(code: 'customer_merged', message: 'Merged customers cannot be blacklisted'),
        );
      }

      final updated = Customer(
        id: customer.id,
        displayName: customer.displayName,
        status: CustomerStatus.blacklisted,
        createdAt: customer.createdAt,
        updatedAt: clock.now(),
      );
      final saved = await customers.save(updated);
      if (saved is Failure<void>) return Failure(saved.error);
      return _audit(
        entityType: 'customer',
        entityId: customer.id,
        action: 'blacklisted',
      );
    });
  }

  @override
  Future<Result<void>> addIdentifier({
    required String customerId,
    required CustomerIdentifierType type,
    required String value,
    required bool isPrimary,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_identifier', message: 'Identifier is required'),
        ),
      );
    }

    return unitOfWork.run(() async {
      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (customer.status != CustomerStatus.active) {
        return const Failure(
          AppFailure(
            code: 'customer_not_active',
            message: 'Identifiers can only be added to active customers',
          ),
        );
      }

      final duplicate = await customers.findByIdentifier(trimmed);
      if (duplicate is Failure<Customer?>) return Failure(duplicate.error);
      if ((duplicate as Success<Customer?>).value != null) {
        return const Failure(
          AppFailure(code: 'duplicate_identifier', message: 'Identifier already exists'),
        );
      }

      final saved = await customers.saveIdentifier(
        CustomerIdentifier(
          id: ids.next('identifier'),
          customerId: customerId,
          type: type,
          value: trimmed,
          isPrimary: isPrimary,
        ),
      );
      if (saved is Failure<void>) return Failure(saved.error);
      return _audit(
        entityType: 'customer',
        entityId: customerId,
        action: 'identifier_added',
        payloadJson: '{"identifier":"$trimmed"}',
      );
    });
  }

  Future<Result<void>> _audit({
    required String entityType,
    required String entityId,
    required String action,
    String? payloadJson,
  }) {
    return auditLogs.append(
      AuditLog(
        id: ids.next('audit'),
        entityType: entityType,
        entityId: entityId,
        action: action,
        payloadJson: payloadJson,
        occurredAt: clock.now(),
      ),
    );
  }
}
