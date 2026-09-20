import '../../core/result.dart';
import '../entities/customer.dart';
import '../entities/pos_account.dart';
import '../entities/wallet.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import 'default_pos_templates_seeder.dart';
import 'local_pos_account_registry.dart';
import 'services.dart';

/// نتيجة إنشاء أو تحديث ملف نقطة البيع (الكتالوج + الدفتر + الربط + القوالب).
final class PosProfile {
  const PosProfile({required this.pointOfSale, required this.account});

  final PointOfSale pointOfSale;
  final PosAccount account;
}

/// مصدر واحد لملف نقطة البيع: التحقق ثم الإنشاء/التعديل وزرع القوالب.
final class LocalPosProfileService {
  const LocalPosProfileService({
    required this.posCatalog,
    required this.posRegistry,
    required this.pointsOfSale,
    required this.customers,
    required this.customerService,
    required this.templates,
  });

  final PointOfSaleCatalogService posCatalog;
  final LocalPosAccountRegistry posRegistry;
  final PointOfSaleRepository pointsOfSale;
  final CustomerRepository customers;
  final CustomerService customerService;
  final TransferTemplateRepository templates;

  Future<String?> validate({
    required String name,
    required String phone,
    String? existingPosId,
    String? existingCustomerId,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty) return 'أدخل اسم نقطة البيع';
    if (trimmedPhone.isEmpty) return 'أدخل رقم جوال نقطة البيع';

    final listed = await pointsOfSale.listAll();
    if (listed is Failure<List<PointOfSale>>) return listed.error.message;
    for (final item in (listed as Success<List<PointOfSale>>).value) {
      if (existingPosId != null && item.id == existingPosId) continue;
      if (item.name.trim() == trimmedName) {
        return 'يوجد نقطة بيع أخرى بنفس الاسم';
      }
    }

    final owner = await posRegistry.findByIdentifier(trimmedPhone);
    if (owner is Failure<PosAccount?>) return owner.error.message;
    final foundPos = (owner as Success<PosAccount?>).value;
    if (foundPos != null && foundPos.posId != (existingPosId ?? '')) {
      return 'الرقم مرتبط بنقطة بيع أخرى: ${foundPos.name}';
    }

    final customer = await customers.findByIdentifier(trimmedPhone);
    if (customer is Failure<Customer?>) return customer.error.message;
    final foundCustomer = (customer as Success<Customer?>).value;
    if (foundCustomer != null && foundCustomer.id != (existingCustomerId ?? '')) {
      return 'الرقم مسجّل لحساب عميل آخر — استخدم رقماً مختلفاً لنقطة البيع';
    }
    return null;
  }

  Future<Result<PosProfile>> create({
    required String name,
    required String phone,
    PosPercentageMode percentageMode = PosPercentageMode.defaultCategory,
    int? creditLimitMinorUnits,
  }) async {
    final problem = await validate(name: name, phone: phone);
    if (problem != null) {
      return Failure(AppFailure(code: 'pos_profile_invalid', message: problem));
    }

    final storedPhone = PhoneNormalizer.forStorage(phone.trim(), asPhone: true);
    final customerResult = await customerService.create(
      displayName: name.trim(),
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: storedPhone,
    );
    if (customerResult is Failure<Customer>) {
      return Failure(customerResult.error);
    }
    final customer = (customerResult as Success<Customer>).value;

    final posResult = await posCatalog.savePointOfSale(name: name.trim());
    if (posResult is Failure<PointOfSale>) return Failure(posResult.error);
    final pos = (posResult as Success<PointOfSale>).value;

    final account = PosAccount(
      posId: pos.id,
      customerId: customer.id,
      name: name.trim(),
      identifiers: [storedPhone],
      notifyPhone: storedPhone,
      percentageMode: percentageMode,
      creditLimitMinorUnits: creditLimitMinorUnits,
    );
    final savedAccount = await posRegistry.save(account);
    if (savedAccount is Failure<void>) return Failure(savedAccount.error);

    final seeded = await DefaultPosTemplatesSeeder(templates: templates)
        .seedForPos(posId: pos.id, posName: name.trim());
    if (seeded is Failure<int>) return Failure(seeded.error);

    return Success(PosProfile(pointOfSale: pos, account: account));
  }

  Future<Result<PosProfile>> update({
    required String posId,
    required PointOfSaleStatus status,
    required String name,
    required String phone,
    required PosAccount existingAccount,
    PosPercentageMode? percentageMode,
    int? creditLimitMinorUnits,
    bool clearCreditLimit = false,
  }) async {
    final problem = await validate(
      name: name,
      phone: phone,
      existingPosId: posId,
      existingCustomerId: existingAccount.customerId,
    );
    if (problem != null) {
      return Failure(AppFailure(code: 'pos_profile_invalid', message: problem));
    }

    final storedPhone = PhoneNormalizer.forStorage(phone.trim(), asPhone: true);
    final posUpdate = await posCatalog.updatePointOfSale(
      id: posId,
      name: name.trim(),
      status: status,
    );
    if (posUpdate is Failure<PointOfSale>) return Failure(posUpdate.error);
    final pos = (posUpdate as Success<PointOfSale>).value;

    final nextAccount = existingAccount.copyWith(
      name: name.trim(),
      identifiers: [storedPhone],
      notifyPhone: storedPhone,
      percentageMode: percentageMode,
      creditLimitMinorUnits: creditLimitMinorUnits,
      clearCreditLimit: clearCreditLimit,
    );
    final savedAccount = await posRegistry.save(nextAccount);
    if (savedAccount is Failure<void>) return Failure(savedAccount.error);

    return Success(PosProfile(pointOfSale: pos, account: nextAccount));
  }
}
