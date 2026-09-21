import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../phone_normalizer.dart';
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
    CustomerStatus status = CustomerStatus.active,
  }) {
    final name = displayName.trim();
    final value = identifierValue.trim();
    if (name.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_display_name', message: 'اسم العميل مطلوب'),
        ),
      );
    }
    if (value.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_identifier', message: 'المعرّف مطلوب (رقم جوال أو اسم مرسل)'),
        ),
      );
    }

    final storedValue = PhoneNormalizer.forStorage(
      value,
      asPhone: identifierType == CustomerIdentifierType.phoneNumber,
    );
    if (identifierType == CustomerIdentifierType.phoneNumber &&
        !PhoneNormalizer.isPhoneLike(value)) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'invalid_phone_identifier',
            message: 'رقم الجوال غير صالح',
          ),
        ),
      );
    }

    return unitOfWork.run(() async {
      final existing = await customers.findByIdentifier(storedValue);
      if (existing is Failure<Customer?>) return Failure(existing.error);
      if ((existing as Success<Customer?>).value != null) {
        return const Failure(
          AppFailure(code: 'duplicate_identifier', message: 'هذا الرقم مسجّل لحساب موجود بالفعل — افتح الحساب الموجود أو استخدم رقماً مختلفاً'),
        );
      }

      final now = clock.now();
      final initialStatus = status == CustomerStatus.provisional
          ? CustomerStatus.provisional
          : CustomerStatus.active;
      final customer = Customer(
        id: ids.next('customer'),
        displayName: name,
        status: initialStatus,
        createdAt: now,
        updatedAt: now,
      );
      final saved = await customers.save(customer);
      if (saved is Failure<void>) return Failure(saved.error);

      final identifier = CustomerIdentifier(
        id: ids.next('identifier'),
        customerId: customer.id,
        type: identifierType,
        value: storedValue,
        isPrimary: true,
      );
      final savedIdentifier = await customers.saveIdentifier(identifier);
      if (savedIdentifier is Failure<void>) return Failure(savedIdentifier.error);

      final audited = await _audit(
        entityType: 'customer',
        entityId: customer.id,
        action: 'created',
        payloadJson:
            '{"identifier":"$storedValue","status":"${initialStatus.name}"}',
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(customer);
    });
  }

  @override
  Future<Result<Customer>> promoteToActive(String customerId) {
    return unitOfWork.run(() async {
      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'الحساب غير موجود'),
        );
      }
      if (customer.status == CustomerStatus.active) {
        return Success(customer);
      }
      if (customer.status != CustomerStatus.provisional) {
        return const Failure(
          AppFailure(code: 'customer_not_promotable', message: 'لا يمكن اعتماد هذا الحساب كعميل'),
        );
      }
      final updated = Customer(
        id: customer.id,
        displayName: customer.displayName,
        status: CustomerStatus.active,
        createdAt: customer.createdAt,
        updatedAt: clock.now(),
        mergedIntoId: customer.mergedIntoId,
      );
      final saved = await customers.save(updated);
      if (saved is Failure<void>) return Failure(saved.error);
      final audited = await _audit(
        entityType: 'customer',
        entityId: customer.id,
        action: 'promoted_to_active',
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(updated);
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
          AppFailure(code: 'customer_not_found', message: 'الحساب غير موجود'),
        );
      }
      if (customer.status == CustomerStatus.merged) {
        return const Failure(
          AppFailure(code: 'customer_merged', message: 'لا يمكن حظر حساب مدموج'),
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
          AppFailure(code: 'invalid_identifier', message: 'المعرّف مطلوب (رقم جوال أو اسم مرسل)'),
        ),
      );
    }
    if (type == CustomerIdentifierType.phoneNumber &&
        !PhoneNormalizer.isPhoneLike(trimmed)) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'invalid_phone_identifier',
            message: 'رقم الجوال غير صالح',
          ),
        ),
      );
    }
    final storedValue = PhoneNormalizer.forStorage(
      trimmed,
      asPhone: type == CustomerIdentifierType.phoneNumber,
    );

    return unitOfWork.run(() async {
      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(
            code: 'customer_not_found',
            message: 'الحساب غير موجود',
          ),
        );
      }
      if (customer.status != CustomerStatus.active) {
        return const Failure(
          AppFailure(
            code: 'customer_not_active',
            message: 'لا يمكن إضافة معرّفات إلا لحساب نشط',
          ),
        );
      }

      final duplicate = await customers.findByIdentifier(storedValue);
      if (duplicate is Failure<Customer?>) return Failure(duplicate.error);
      if ((duplicate as Success<Customer?>).value != null) {
        return const Failure(
          AppFailure(code: 'duplicate_identifier', message: 'هذا الرقم مسجّل لحساب موجود بالفعل — افتح الحساب الموجود أو استخدم رقماً مختلفاً'),
        );
      }

      final saved = await customers.saveIdentifier(
        CustomerIdentifier(
          id: ids.next('identifier'),
          customerId: customerId,
          type: type,
          value: storedValue,
          isPrimary: isPrimary,
        ),
      );
      if (saved is Failure<void>) return Failure(saved.error);
      return _audit(
        entityType: 'customer',
        entityId: customerId,
        action: 'identifier_added',
        payloadJson: '{"identifier":"$storedValue"}',
      );
    });
  }

  @override
  Future<Result<void>> bindPrimaryGsm({
    required String customerId,
    required String phone,
  }) {
    final trimmed = phone.trim();
    if (!PhoneNormalizer.isPhoneLike(trimmed)) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'invalid_phone_identifier',
            message: 'رقم الجوال غير صالح',
          ),
        ),
      );
    }
    final stored = PhoneNormalizer.forStorage(trimmed, asPhone: true);

    return unitOfWork.run(() async {
      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'الحساب غير موجود'),
        );
      }
      if (customer.status != CustomerStatus.active) {
        return const Failure(
          AppFailure(
            code: 'customer_not_active',
            message: 'لا يمكن ربط جوال لحساب غير نشط',
          ),
        );
      }

      final existingIds = await customers.listIdentifiers(customerId);
      if (existingIds is Failure<List<CustomerIdentifier>>) {
        return Failure(existingIds.error);
      }
      final idsList = (existingIds as Success<List<CustomerIdentifier>>).value;
      final alreadyHasPhone = idsList.any(
        (i) => i.type == CustomerIdentifierType.phoneNumber,
      );
      if (alreadyHasPhone) {
        return const Success(null);
      }

      final conflict = await customers.findByIdentifier(stored);
      if (conflict is Failure<Customer?>) return Failure(conflict.error);
      final other = (conflict as Success<Customer?>).value;
      if (other != null && other.id != customerId) {
        return const Failure(
          AppFailure(
            code: 'gsm_conflict',
            message: 'رقم الجوال مربوط بحساب آخر — استخدم الدمج يدويًا',
          ),
        );
      }

      final saved = await customers.saveIdentifier(
        CustomerIdentifier(
          id: ids.next('identifier'),
          customerId: customerId,
          type: CustomerIdentifierType.phoneNumber,
          value: stored,
          isPrimary: true,
        ),
      );
      if (saved is Failure<void>) return Failure(saved.error);

      return _audit(
        entityType: 'customer',
        entityId: customerId,
        action: 'bind_primary_gsm',
        payloadJson: '{"phone":"$stored"}',
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
        occurredAt: clock.now(),
        payloadJson: payloadJson,
      ),
    );
  }
}
