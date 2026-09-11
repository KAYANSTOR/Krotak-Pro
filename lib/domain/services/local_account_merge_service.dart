import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';

/// Merges [sourceCustomerId] into [targetCustomerId].
///
/// Rules derived from schema (`mergedIntoId`, `CustomerStatus.merged`) and
/// existing customer service constraints:
/// - source and target must exist and be distinct
/// - target must be `active`
/// - source must be `active` (not already merged/blacklisted/archived)
/// - all identifiers of source move to target (skip exact duplicate values)
/// - completed ledger rows of source are **not** auto-moved; balance
///   consolidation must be explicit via settlement/credit
/// - idempotent if source already merged into the same target
final class LocalAccountMergeService {
  const LocalAccountMergeService({
    required this.customers,
    required this.transactions,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final CustomerRepository customers;
  final TransactionRepository transactions;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  Future<Result<Customer>> merge({
    required String sourceCustomerId,
    required String targetCustomerId,
  }) {
    if (sourceCustomerId == targetCustomerId) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'merge_same_customer',
            message: 'Cannot merge a customer into itself',
          ),
        ),
      );
    }

    return unitOfWork.run(() async {
      final sourceResult = await customers.findById(sourceCustomerId);
      if (sourceResult is Failure<Customer?>) return Failure(sourceResult.error);
      final source = (sourceResult as Success<Customer?>).value;
      if (source == null) {
        return const Failure(
          AppFailure(code: 'source_not_found', message: 'Source customer not found'),
        );
      }

      final targetResult = await customers.findById(targetCustomerId);
      if (targetResult is Failure<Customer?>) return Failure(targetResult.error);
      final target = (targetResult as Success<Customer?>).value;
      if (target == null) {
        return const Failure(
          AppFailure(code: 'target_not_found', message: 'Target customer not found'),
        );
      }

      if (source.status == CustomerStatus.merged &&
          source.mergedIntoId == targetCustomerId) {
        return Success(source);
      }

      if (source.status != CustomerStatus.active) {
        return Failure(
          AppFailure(
            code: 'source_not_mergeable',
            message: 'Source status is ${source.status.name}',
          ),
        );
      }
      if (target.status != CustomerStatus.active) {
        return Failure(
          AppFailure(
            code: 'target_not_mergeable',
            message: 'Target status is ${target.status.name}',
          ),
        );
      }

      final idsResult = await customers.listIdentifiers(sourceCustomerId);
      if (idsResult is Failure<List<CustomerIdentifier>>) {
        return Failure(idsResult.error);
      }
      final sourceIds = (idsResult as Success<List<CustomerIdentifier>>).value;

      for (final identifier in sourceIds) {
        final existing = await customers.findByIdentifier(identifier.value);
        if (existing is Failure<Customer?>) return Failure(existing.error);
        final owner = (existing as Success<Customer?>).value;
        if (owner != null && owner.id == targetCustomerId) {
          continue;
        }
        if (owner != null && owner.id != sourceCustomerId) {
          return Failure(
            AppFailure(
              code: 'identifier_conflict',
              message: 'Identifier ${identifier.value} belongs to another customer',
            ),
          );
        }

        final moved = await customers.saveIdentifier(
          CustomerIdentifier(
            id: identifier.id,
            customerId: targetCustomerId,
            type: identifier.type,
            value: identifier.value,
            isPrimary: false,
          ),
        );
        if (moved is Failure<void>) return Failure(moved.error);
      }

      final now = clock.now();
      final mergedSource = source.copyWith(
        status: CustomerStatus.merged,
        mergedIntoId: targetCustomerId,
        updatedAt: now,
      );
      final saved = await customers.save(mergedSource);
      if (saved is Failure<void>) return Failure(saved.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'customer',
          entityId: sourceCustomerId,
          action: 'merged',
          payloadJson:
              '{"into":"$targetCustomerId","identifiersMoved":${sourceIds.length}}',
          occurredAt: now,
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);

      return Success(mergedSource);
    });
  }
}
