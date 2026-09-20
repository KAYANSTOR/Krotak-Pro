import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/pos_account.dart';
import '../entities/pos_profile.dart';
import '../entities/wallet.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'default_pos_templates_seeder.dart';
import 'local_pos_account_registry.dart';
import 'services.dart';

/// Single mutation and read boundary for a complete point-of-sale profile.
/// UI code must not create/update the catalog, customer, POS account, or
/// default POS templates independently.
final class LocalPointOfSaleProfileService implements PointOfSaleProfileService {
  const LocalPointOfSaleProfileService({
    required this.customers,
    required this.pointsOfSale,
    required this.posRegistry,
    required this.templates,
    required this.auditLogs,
    required this.unitOfWork,
    required this.balanceService,
    required this.clock,
    required this.ids,
  });

  final CustomerRepository customers;
  final PointOfSaleRepository pointsOfSale;
  final LocalPosAccountRegistry posRegistry;
  final TransferTemplateRepository templates;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final CustomerBalanceService balanceService;
  final Clock clock;
  final IdGenerator ids;

  @override
  Future<Result<List<PointOfSaleProfile>>> listPointOfSaleProfiles({
    bool includeArchived = true,
  }) async {
    final positions = await pointsOfSale.listAll();
    if (positions is Failure<List<PointOfSale>>) return Failure(positions.error);

    final accounts = await posRegistry.listAll();
    if (accounts is Failure<List<PosAccount>>) return Failure(accounts.error);

    final byPosId = <String, PosAccount>{
      for (final account in (accounts as Success<List<PosAccount>>).value)
        account.posId: account,
    };

    final profiles = <PointOfSaleProfile>[];
    for (final pos in (positions as Success<List<PointOfSale>>).value) {
      if (!includeArchived && pos.status == PointOfSaleStatus.archived) continue;

      final account = byPosId[pos.id];
      Customer? customer;
      Money? balance;

      if (account != null) {
        final customerResult = await customers.findById(account.customerId);
        if (customerResult is Success<Customer?>) {
          customer = customerResult.value;
        }

        final balanceResult = await balanceService.getBalance(
          customerId: account.customerId,
          currencyCode: 'YER',
        );
        if (balanceResult is Success<Money>) {
          balance = balanceResult.value;
        }
      }

      profiles.add(
        PointOfSaleProfile(
          pointOfSale: pos,
          account: account,
          customer: customer,
          balance: balance,
        ),
      );
    }

    return Success(profiles);
  }

  @override
  Future<Result<PointOfSaleProfile>> createPointOfSaleProfile({
    required String name,
    required String phone,
    required int? creditLimitMinorUnits,
    required PosPercentageMode percentageMode,
  }) async {
    final normalizedName = name.trim();
    final normalizedInputPhone = phone.trim();
    final validation = _validateInput(normalizedName, normalizedInputPhone);
    if (validation != null) return Failure(validation);

    final storedPhone = PhoneNormalizer.forStorage(
      normalizedInputPhone,
      asPhone: true,
    );

    return unitOfWork.run(() async {
      final duplicateName = await _nameExists(normalizedName);
      if (duplicateName is Failure<bool>) return Failure(duplicateName.error);
      if ((duplicateName as Success<bool>).value) {
        return const Failure(
          AppFailure(
            code: 'duplicate_pos_name',
            message: 'يوجد نقطة بيع أخرى بنفس الاسم',
          ),
        );
      }

      final linkedPos = await posRegistry.findByIdentifierAnyStatus(storedPhone);
      if (linkedPos is Failure<PosAccount?>) return Failure(linkedPos.error);
      if ((linkedPos as Success<PosAccount?>).value != null) {
        return const Failure(
          AppFailure(
            code: 'duplicate_pos_phone',
            message: 'رقم الجوال مرتبط مسبقاً بنقطة بيع أخرى',
          ),
        );
      }

      final existingCustomer = await customers.findByIdentifier(storedPhone);
      if (existingCustomer is Failure<Customer?>) return Failure(existingCustomer.error);
      if ((existingCustomer as Success<Customer?>).value != null) {
        return const Failure(
          AppFailure(
            code: 'pos_phone_used_by_customer',
            message: 'رقم الجوال مسجّل مسبقاً لحساب عميل',
          ),
        );
      }

      final now = clock.now();
      final customer = Customer(
        id: ids.next('customer'),
        displayName: normalizedName,
        status: CustomerStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final savedCustomer = await customers.save(customer);
      if (savedCustomer is Failure<void>) return Failure(savedCustomer.error);

      final savedIdentifier = await customers.saveIdentifier(
        CustomerIdentifier(
          id: ids.next('identifier'),
          customerId: customer.id,
          type: CustomerIdentifierType.phoneNumber,
          value: storedPhone,
          isPrimary: true,
        ),
      );
      if (savedIdentifier is Failure<void>) return Failure(savedIdentifier.error);

      final pos = PointOfSale(
        id: ids.next('pos'),
        name: normalizedName,
        status: PointOfSaleStatus.active,
        createdAt: now,
      );
      final savedPos = await pointsOfSale.save(pos);
      if (savedPos is Failure<void>) return Failure(savedPos.error);

      final account = PosAccount(
        posId: pos.id,
        customerId: customer.id,
        name: normalizedName,
        identifiers: [storedPhone],
        notifyPhone: storedPhone,
        percentageMode: percentageMode,
        creditLimitMinorUnits: creditLimitMinorUnits,
      );
      final savedAccount = await posRegistry.save(account);
      if (savedAccount is Failure<void>) return Failure(savedAccount.error);

      final seeded = await DefaultPosTemplatesSeeder(templates: templates)
          .seedForPos(posId: pos.id, posName: normalizedName);
      if (seeded is Failure<int>) return Failure(seeded.error);

      final audit = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'point_of_sale',
          entityId: pos.id,
          action: 'profile_created',
          payloadJson:
              '{"customerId":"${customer.id}","phone":"$storedPhone","templateCount":${(seeded as Success<int>).value}}',
          occurredAt: now,
        ),
      );
      if (audit is Failure<void>) return Failure(audit.error);

      return Success(
        PointOfSaleProfile(
          pointOfSale: pos,
          account: account,
          customer: customer,
          balance: null,
        ),
      );
    });
  }

  @override
  Future<Result<PointOfSaleProfile>> updatePointOfSaleProfile({
    required String id,
    required String name,
    required String phone,
    required int? creditLimitMinorUnits,
    required PosPercentageMode percentageMode,
    required PointOfSaleStatus status,
  }) async {
    final normalizedName = name.trim();
    final normalizedInputPhone = phone.trim();
    final validation = _validateInput(normalizedName, normalizedInputPhone);
    if (validation != null) return Failure(validation);

    final storedPhone = PhoneNormalizer.forStorage(
      normalizedInputPhone,
      asPhone: true,
    );

    return unitOfWork.run(() async {
      final foundPos = await pointsOfSale.findById(id);
      if (foundPos is Failure<PointOfSale?>) return Failure(foundPos.error);
      final pos = (foundPos as Success<PointOfSale?>).value;
      if (pos == null) {
        return const Failure(
          AppFailure(code: 'pos_not_found', message: 'نقطة البيع غير موجودة'),
        );
      }

      final accountResult = await posRegistry.findByPosId(id);
      if (accountResult is Failure<PosAccount?>) return Failure(accountResult.error);
      final account = (accountResult as Success<PosAccount?>).value;
      if (account == null) {
        return const Failure(
          AppFailure(
            code: 'pos_account_missing',
            message: 'بيانات الحساب غير مكتملة — يلزم استكمال ربط نقطة البيع',
          ),
        );
      }

      final duplicateName = await _nameExists(normalizedName, excludingId: id);
      if (duplicateName is Failure<bool>) return Failure(duplicateName.error);
      if ((duplicateName as Success<bool>).value) {
        return const Failure(
          AppFailure(
            code: 'duplicate_pos_name',
            message: 'يوجد نقطة بيع أخرى بنفس الاسم',
          ),
        );
      }

      final owner = await posRegistry.findByIdentifierAnyStatus(storedPhone);
      if (owner is Failure<PosAccount?>) return Failure(owner.error);
      final ownerAccount = (owner as Success<PosAccount?>).value;
      if (ownerAccount != null && ownerAccount.posId != id) {
        return const Failure(
          AppFailure(
            code: 'duplicate_pos_phone',
            message: 'رقم الجوال مرتبط مسبقاً بنقطة بيع أخرى',
          ),
        );
      }

      final customerWithPhone = await customers.findByIdentifier(storedPhone);
      if (customerWithPhone is Failure<Customer?>) return Failure(customerWithPhone.error);
      final customer = (customerWithPhone as Success<Customer?>).value;
      if (customer != null && customer.id != account.customerId) {
        return const Failure(
          AppFailure(
            code: 'pos_phone_used_by_customer',
            message: 'رقم الجوال مسجّل مسبقاً لحساب عميل آخر',
          ),
        );
      }

      final updatedPos = PointOfSale(
        id: pos.id,
        name: normalizedName,
        status: status,
        createdAt: pos.createdAt,
      );
      final savedPos = await pointsOfSale.save(updatedPos);
      if (savedPos is Failure<void>) return Failure(savedPos.error);

      final updatedAccount = account.copyWith(
        name: normalizedName,
        identifiers: [storedPhone],
        notifyPhone: storedPhone,
        percentageMode: percentageMode,
        creditLimitMinorUnits: creditLimitMinorUnits,
        clearCreditLimit: creditLimitMinorUnits == null,
        status: status,
      );
      final savedAccount = await posRegistry.save(updatedAccount);
      if (savedAccount is Failure<void>) return Failure(savedAccount.error);

      final audit = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'point_of_sale',
          entityId: id,
          action: status != pos.status ? 'status_changed' : 'updated',
          payloadJson:
              '{"status":"${status.name}","phone":"$storedPhone"}',
          occurredAt: clock.now(),
        ),
      );
      if (audit is Failure<void>) return Failure(audit.error);

      final resolvedCustomer = customer?.id == account.customerId
          ? customer
          : (await customers.findById(account.customerId) as Success<Customer?>).value;

      return Success(
        PointOfSaleProfile(
          pointOfSale: updatedPos,
          account: updatedAccount,
          customer: resolvedCustomer,
          balance: null,
        ),
      );
    });
  }

  @override
  Future<Result<PointOfSaleProfile>> setPointOfSaleStatus({
    required String id,
    required PointOfSaleStatus status,
  }) async {
    return unitOfWork.run(() async {
      final foundPos = await pointsOfSale.findById(id);
      if (foundPos is Failure<PointOfSale?>) return Failure(foundPos.error);
      final pos = (foundPos as Success<PointOfSale?>).value;
      if (pos == null) {
        return const Failure(
          AppFailure(code: 'pos_not_found', message: 'نقطة البيع غير موجودة'),
        );
      }

      final accountResult = await posRegistry.findByPosId(id);
      if (accountResult is Failure<PosAccount?>) return Failure(accountResult.error);
      final account = (accountResult as Success<PosAccount?>).value;

      final updatedPos = PointOfSale(
        id: pos.id,
        name: pos.name,
        status: status,
        createdAt: pos.createdAt,
      );
      final savedPos = await pointsOfSale.save(updatedPos);
      if (savedPos is Failure<void>) return Failure(savedPos.error);

      PosAccount? updatedAccount = account;
      if (account != null) {
        updatedAccount = account.copyWith(status: status);
        final savedAccount = await posRegistry.save(updatedAccount);
        if (savedAccount is Failure<void>) return Failure(savedAccount.error);
      }

      final audit = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'point_of_sale',
          entityId: id,
          action: status == PointOfSaleStatus.archived ? 'archived' : 'status_changed',
          payloadJson: '{"status":"${status.name}"}',
          occurredAt: clock.now(),
        ),
      );
      if (audit is Failure<void>) return Failure(audit.error);

      Customer? customer;
      if (updatedAccount != null) {
        final foundCustomer = await customers.findById(updatedAccount.customerId);
        if (foundCustomer is Success<Customer?>) customer = foundCustomer.value;
      }

      return Success(
        PointOfSaleProfile(
          pointOfSale: updatedPos,
          account: updatedAccount,
          customer: customer,
          balance: null,
        ),
      );
    });
  }

  @override
  Future<Result<PointOfSaleProfile>> archivePointOfSale(String id) {
    return setPointOfSaleStatus(
      id: id,
      status: PointOfSaleStatus.archived,
    );
  }

  Future<Result<bool>> _nameExists(
    String name, {
    String? excludingId,
  }) async {
    final positions = await pointsOfSale.listAll();
    if (positions is Failure<List<PointOfSale>>) return Failure(positions.error);
    final needle = name.trim().toLowerCase();
    return Success(
      (positions as Success<List<PointOfSale>>).value.any(
        (item) => item.id != excludingId && item.name.trim().toLowerCase() == needle,
      ),
    );
  }

  AppFailure? _validateInput(String name, String phone) {
    if (name.isEmpty) {
      return const AppFailure(
        code: 'invalid_pos_name',
        message: 'اسم نقطة البيع مطلوب',
      );
    }
    if (!PhoneNormalizer.isPhoneLike(phone)) {
      return const AppFailure(
        code: 'invalid_pos_phone',
        message: 'رقم جوال نقطة البيع غير صالح',
      );
    }
    return null;
  }
}
