import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/money.dart';

abstract interface class AdvanceService {
  Future<Result<AdvanceIssue>> request({
    required String customerId,
    required String currencyCode,
    required String operationId,
  });

  Future<Result<AdvanceIssue>> requestByIdentifier({
    required String identifier,
    required String currencyCode,
    required String operationId,
  });

  Future<Result<AdvancePaymentResult>> applyPayment({
    required String customerId,
    required Money amount,
    required String reference,
  });

  Future<Result<List<Advance>>> listCustomerAdvances(String customerId);
}
