import '../../core/result.dart';
import '../entities/customer.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Result of mapping a transfer identifier to a customer and delivery phone.
///
/// [Unresolved] is explicit — never guess a customer or send to a non-phone token.
final class CustomerIdentityResolution {
  const CustomerIdentityResolution.resolved({
    required this.customer,
    required this.deliveryPhone,
    required this.matchedIdentifier,
  })  : isResolved = true,
        reasonCode = null,
        reasonMessage = null;

  const CustomerIdentityResolution.unresolved({
    required this.reasonCode,
    required this.reasonMessage,
  })  : customer = null,
        deliveryPhone = null,
        matchedIdentifier = null,
        isResolved = false;

  final bool isResolved;
  final Customer? customer;

  /// Primary phone suitable for SMS delivery; null when identity is resolved
  /// only by account/name and no phone is on file (credit may still proceed).
  final String? deliveryPhone;

  final CustomerIdentifier? matchedIdentifier;
  final String? reasonCode;
  final String? reasonMessage;
}

/// Resolves transfer identifiers to customers without commercial side effects.
final class LocalCustomerIdentityResolver {
  const LocalCustomerIdentityResolver({
    required this.customers,
  });

  final CustomerRepository customers;

  Future<Result<CustomerIdentityResolution>> resolve({
    required String identifierValue,
    required TransferIdentifierType identifierType,
  }) async {
    final trimmed = identifierValue.trim();
    if (trimmed.isEmpty) {
      return const Success(
        CustomerIdentityResolution.unresolved(
          reasonCode: 'empty_identifier',
          reasonMessage: 'Transfer identifier is empty',
        ),
      );
    }

    if (identifierType == TransferIdentifierType.phone) {
      if (!_looksLikePhone(trimmed)) {
        return const Success(
          CustomerIdentityResolution.unresolved(
            reasonCode: 'invalid_phone_identifier',
            reasonMessage: 'Phone identifier is not a sendable number',
          ),
        );
      }
    }

    final found = await customers.findByIdentifier(trimmed);
    if (found is Failure<Customer?>) {
      return Failure(found.error);
    }
    final customer = (found as Success<Customer?>).value;
    if (customer == null) {
      return Success(
        CustomerIdentityResolution.unresolved(
          reasonCode: 'customer_not_found',
          reasonMessage:
              'No customer mapping for ${identifierType.name}: $trimmed',
        ),
      );
    }
    if (customer.status == CustomerStatus.merged &&
        customer.mergedIntoId != null) {
      final survivor = await customers.findById(customer.mergedIntoId!);
      if (survivor is Failure<Customer?>) {
        return Failure(survivor.error);
      }
      final live = (survivor as Success<Customer?>).value;
      if (live == null || live.status != CustomerStatus.active) {
        return const Success(
          CustomerIdentityResolution.unresolved(
            reasonCode: 'merged_target_inactive',
            reasonMessage: 'Merged customer target is not active',
          ),
        );
      }
      return _withDeliveryPhone(live, trimmed);
    }
    if (customer.status != CustomerStatus.active) {
      return Success(
        CustomerIdentityResolution.unresolved(
          reasonCode: 'customer_not_active',
          reasonMessage: 'Customer status is ${customer.status.name}',
        ),
      );
    }
    return _withDeliveryPhone(customer, trimmed);
  }

  Future<Result<CustomerIdentityResolution>> _withDeliveryPhone(
    Customer customer,
    String matchedValue,
  ) async {
    final idsResult = await customers.listIdentifiers(customer.id);
    if (idsResult is Failure<List<CustomerIdentifier>>) {
      return Failure(idsResult.error);
    }
    final ids = (idsResult as Success<List<CustomerIdentifier>>).value;
    CustomerIdentifier? matched;
    for (final id in ids) {
      if (id.value == matchedValue) {
        matched = id;
        break;
      }
    }
    String? delivery;
    for (final id in ids) {
      if (id.type == CustomerIdentifierType.phoneNumber && id.isPrimary) {
        delivery = id.value;
        break;
      }
    }
    delivery ??= ids
        .where((id) => id.type == CustomerIdentifierType.phoneNumber)
        .map((id) => id.value)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);

    return Success(
      CustomerIdentityResolution.resolved(
        customer: customer,
        deliveryPhone: delivery,
        matchedIdentifier: matched,
      ),
    );
  }

  bool _looksLikePhone(String value) {
    if (value.startsWith('+')) {
      final rest = value.substring(1).replaceAll(RegExp(r'\D'), '');
      return rest.length >= 7 && rest.length <= 15;
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7 && digits.length <= 15;
  }
}
