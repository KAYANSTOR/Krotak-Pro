import '../../core/result.dart';
import '../entities/customer.dart';
import '../phone_normalizer.dart';
import '../repositories/repositories.dart';
import 'local_account_merge_service.dart';
import 'services.dart';

/// ما سيحدث عند ربط حساب برقم فعلي: ربط الرقم بنفس الحساب، أو دمجه في حساب
/// موجود يملك الرقم أصلاً.
final class IdentityLinkPreview {
  const IdentityLinkPreview({required this.phone, this.owner});

  /// الرقم بصيغة التخزين.
  final String phone;

  /// الحساب الذي يملك الرقم حالياً (null = الرقم حر).
  final Customer? owner;

  bool get willMerge => owner != null;
}

/// ربط «الرقم البديل» (مرسل مخفي) برقم العميل الفعلي.
final class LocalIdentityLinkService {
  const LocalIdentityLinkService({
    required this.customers,
    required this.customerService,
    required this.mergeService,
  });

  final CustomerRepository customers;
  final CustomerService customerService;
  final LocalAccountMergeService mergeService;

  Future<Result<IdentityLinkPreview>> preview({
    required String altCustomerId,
    required String phone,
  }) async {
    final trimmed = phone.trim();
    if (!PhoneNormalizer.isPhoneLike(trimmed)) {
      return const Failure(
        AppFailure(code: 'invalid_phone_identifier', message: 'رقم الجوال غير صالح'),
      );
    }
    final stored = PhoneNormalizer.forStorage(trimmed, asPhone: true);

    final found = await customers.findById(altCustomerId);
    if (found is Failure<Customer?>) return Failure(found.error);
    final alt = (found as Success<Customer?>).value;
    if (alt == null) {
      return const Failure(AppFailure(code: 'customer_not_found', message: 'الحساب غير موجود'));
    }

    final ids = await customers.listIdentifiers(altCustomerId);
    if (ids is Failure<List<CustomerIdentifier>>) return Failure(ids.error);
    final hasPhone = (ids as Success<List<CustomerIdentifier>>)
        .value
        .any((i) => i.type == CustomerIdentifierType.phoneNumber);
    if (hasPhone) {
      return const Failure(
        AppFailure(code: 'already_has_phone', message: 'هذا الحساب مرتبط برقم فعلي بالفعل'),
      );
    }

    final ownerResult = await customers.findByIdentifier(stored);
    if (ownerResult is Failure<Customer?>) return Failure(ownerResult.error);
    final owner = (ownerResult as Success<Customer?>).value;
    if (owner != null && owner.id == altCustomerId) {
      return Failure(
        const AppFailure(code: 'already_has_phone', message: 'هذا الحساب مرتبط برقم فعلي بالفعل'),
      );
    }
    return Success(IdentityLinkPreview(phone: stored, owner: owner));
  }

  /// يربط الرقم. يعيد الحساب الذي بقي فعّالاً: نفس الحساب (الرقم حر) أو الحساب
  /// المالك للرقم (بعد دمج الحساب البديل فيه مع حركاته ومبيعاته).
  Future<Result<Customer>> link({
    required String altCustomerId,
    required String phone,
  }) async {
    final p = await preview(altCustomerId: altCustomerId, phone: phone);
    if (p is Failure<IdentityLinkPreview>) return Failure(p.error);
    final plan = (p as Success<IdentityLinkPreview>).value;

    if (plan.owner == null) {
      final bound = await customerService.bindPrimaryGsm(
        customerId: altCustomerId,
        phone: plan.phone,
      );
      if (bound is Failure<void>) return Failure(bound.error);
      final reloaded = await customers.findById(altCustomerId);
      if (reloaded is Failure<Customer?>) return Failure(reloaded.error);
      final customer = (reloaded as Success<Customer?>).value;
      return customer == null
          ? const Failure(AppFailure(code: 'customer_not_found', message: 'الحساب غير موجود'))
          : Success(customer);
    }

    final merged = await mergeService.merge(
      sourceCustomerId: altCustomerId,
      targetCustomerId: plan.owner!.id,
    );
    if (merged is Failure<Customer>) return Failure(merged.error);
    return Success(plan.owner!);
  }
}
