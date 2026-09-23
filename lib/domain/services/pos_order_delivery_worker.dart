import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../entities/money.dart';
import '../entities/pos_account.dart';
import '../repositories/repositories.dart';
import '../entities/wallet.dart';
import 'local_pos_account_registry.dart';
import 'services.dart';
import 'local_message_retry_service.dart';
import 'message_retry_policy.dart';
import 'outbound_message_dispatch_guard.dart';
import 'pos_order_message_renderer.dart';

/// Recovery worker for POS orders that have already committed their cards.
///
/// A POS order has two independent outbound targets:
/// 1. the POS customer's phone (voucher SMS)
/// 2. the POS account's notification phone (operation confirmation)
///
/// The same message/order is reused during retry; no new card is allocated.
final class PosOrderDeliveryWorker {
  const PosOrderDeliveryWorker({
    required this.messages,
    required this.auditLogs,
    required this.cards,
    required this.settings,
    required this.posRegistry,
    required this.messageSender,
    required this.retryService,
    required this.clock,
    required this.ids,
    this.policy = const MessageRetryPolicy(),
  });

  final MessageRepository messages;
  final AuditLogRepository auditLogs;
  final CardRepository cards;
  final SettingsRepository settings;
  final LocalPosAccountRegistry posRegistry;
  final MessageSender messageSender;
  final MessageRetryServicePort retryService;
  final Clock clock;
  final IdGenerator ids;
  final MessageRetryPolicy policy;

  /// Same atomic per-message claim used by the customer-voucher delivery
  /// worker, applied here to close the same duplicate-send window: without it, two
  /// overlapping `tick()` passes (e.g. the periodic recovery timer firing
  /// while a manual kick is still running) could both pass the
  /// `customerDone`/`posDone` checks for the same message before either has
  /// recorded its success audit, and each independently send the SMS.
  OutboundMessageDispatchGuard? get _dispatchGuard {
    final value = messages;
    return value is OutboundMessageStore
        ? OutboundMessageDispatchGuard(store: value as OutboundMessageStore)
        : null;
  }

  Future<Result<PosOrderDeliveryWorkerReport>> tick() async {
    final candidates = await _candidateMessages();
    if (candidates is Failure<List<IncomingMessage>>) {
      return Failure(candidates.error);
    }

    var attempted = 0;
    var delivered = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    for (final message in (candidates as Success<List<IncomingMessage>>).value) {
      final commitResult = await _findCommit(message.id);
      if (commitResult is Failure<_PosOrderCommit?>) {
        failed++;
        errors.add(message.id + ':' + commitResult.error.code);
        continue;
      }
      final commit = (commitResult as Success<_PosOrderCommit?>).value;
      if (commit == null) {
        skipped++;
        continue;
      }

      final customerDone = await _hasSuccess(
        message.id,
        'pos_order_customer_sms_succeeded',
      );
      if (customerDone is Failure<bool>) {
        failed++;
        errors.add(message.id + ':' + customerDone.error.code);
        continue;
      }
      final posDone = await _hasSuccess(
        message.id,
        'pos_order_pos_sms_succeeded',
      );
      if (posDone is Failure<bool>) {
        failed++;
        errors.add(message.id + ':' + posDone.error.code);
        continue;
      }

      final customerDelivered = (customerDone as Success<bool>).value;
      final posDelivered = (posDone as Success<bool>).value;
      if (customerDelivered && posDelivered) {
        await messages.updateStatus(
          message.id,
          MessageProcessingStatus.processed,
        );
        await retryService.clearAfterSuccess(message.id);
        skipped++;
        continue;
      }

      final due = await _isDeliveryDue(message, commit);
      if (due is Failure<bool>) {
        failed++;
        errors.add(message.id + ':' + due.error.code);
        continue;
      }
      if (!(due as Success<bool>).value) {
        skipped++;
        continue;
      }

      final posAccountResult = await posRegistry.findByPosId(commit.posId);
      if (posAccountResult is Failure<PosAccount?>) {
        failed++;
        errors.add(message.id + ':' + posAccountResult.error.code);
        continue;
      }
      final posAccount = (posAccountResult as Success<PosAccount?>).value;
      if (posAccount == null || posAccount.status != PointOfSaleStatus.active) {
        final error = const AppFailure(
          code: 'pos_order_account_unavailable',
          message: 'POS account is missing or inactive',
        );
        await _recordFailure(
          message: message,
          error: error,
          commit: commit,
        );
        failed++;
        errors.add(message.id + ':' + error.code);
        continue;
      }

      final loadedCards = <Card>[];
      var cardsInvalid = false;
      for (final item in commit.items) {
        final found = await cards.findById(item.cardId);
        if (found is Failure<Card?>) {
          await _recordFailure(message: message, error: found.error, commit: commit);
          failed++;
          errors.add(message.id + ':' + found.error.code);
          cardsInvalid = true;
          break;
        }
        final card = (found as Success<Card?>).value;
        if (card == null) {
          const error = AppFailure(
            code: 'pos_order_card_missing',
            message: 'Committed POS card was not found',
          );
          await _recordFailure(message: message, error: error, commit: commit);
          failed++;
          errors.add(message.id + ':' + error.code);
          cardsInvalid = true;
          break;
        }
        loadedCards.add(card);
      }
      if (cardsInvalid) continue;
      if (loadedCards.isEmpty) {
        const error = AppFailure(
          code: 'pos_order_cards_missing',
          message: 'Committed POS order contains no cards',
        );
        await _recordFailure(message: message, error: error, commit: commit);
        failed++;
        errors.add(message.id + ':' + error.code);
        continue;
      }

      final rendered = await PosOrderMessageRenderer(settings: settings).render(
        posAccount: posAccount,
        customerPhone: commit.customerDestination,
        posNotificationPhone: commit.posDestination,
        categoryName: commit.categoryName,
        faceValue: commit.faceValue,
        unitCharge: commit.unitCharge,
        cards: loadedCards,
        quantity: commit.quantity,
      );
      if (rendered is Failure<PosOrderMessages>) {
        await _recordFailure(message: message, error: rendered.error, commit: commit);
        failed++;
        errors.add(message.id + ':' + rendered.error.code);
        continue;
      }
      final body = (rendered as Success<PosOrderMessages>).value;

      final guard = _dispatchGuard;
      if (guard != null) {
        final claimed = await guard.store.claimForDispatch(
          message.id,
          now: clock.now(),
          staleBefore: clock.now().subtract(policy.confirmPendingTimeout),
        );
        if (!claimed) {
          skipped++;
          continue;
        }
      }

      attempted++;
      if (!customerDelivered) {
        final sent = await messageSender.send(
          destination: body.customerDestination,
          body: body.customerBody,
        );
        if (sent is Failure<void>) {
          await auditLogs.append(
            AuditLog(
              id: ids.next('audit'),
              entityType: 'message',
              entityId: message.id,
              action: 'pos_order_customer_sms_failed',
              occurredAt: clock.now(),
              payloadJson: jsonEncode({
                'operationId': commit.operationId,
                'destination': body.customerDestination,
                'error': sent.error.code,
                'source': 'pos_order_delivery_worker',
              }),
            ),
          );
          await _recordFailure(
            message: message,
            error: sent.error,
            commit: commit,
          );
          failed++;
          errors.add(message.id + ':' + sent.error.code);
          continue;
        }

        final successAudit = await auditLogs.append(
          AuditLog(
            id: ids.next('audit'),
            entityType: 'message',
            entityId: message.id,
            action: 'pos_order_customer_sms_succeeded',
            occurredAt: clock.now(),
            payloadJson: jsonEncode({
              'operationId': commit.operationId,
              'destination': body.customerDestination,
              'quantity': commit.quantity,
              'source': 'pos_order_delivery_worker',
            }),
          ),
        );
        if (successAudit is Failure<void>) {
          await _recordFailure(
            message: message,
            error: successAudit.error,
            commit: commit,
          );
          failed++;
          errors.add(message.id + ':' + successAudit.error.code);
          continue;
        }
      }

      final customerSuccessNow = await _hasSuccess(
        message.id,
        'pos_order_customer_sms_succeeded',
      );
      if (customerSuccessNow is Failure<bool> ||
          !(customerSuccessNow as Success<bool>).value) {
        const error = AppFailure(
          code: 'pos_order_customer_sms_state_missing',
          message: 'Customer delivery succeeded but its state was not persisted',
        );
        await _recordFailure(message: message, error: error, commit: commit);
        failed++;
        errors.add(message.id + ':' + error.code);
        continue;
      }

      if (!posDelivered) {
        final sent = await messageSender.send(
          destination: body.posDestination,
          body: body.posBody,
        );
        if (sent is Failure<void>) {
          await auditLogs.append(
            AuditLog(
              id: ids.next('audit'),
              entityType: 'message',
              entityId: message.id,
              action: 'pos_order_pos_sms_failed',
              occurredAt: clock.now(),
              payloadJson: jsonEncode({
                'operationId': commit.operationId,
                'destination': body.posDestination,
                'error': sent.error.code,
                'source': 'pos_order_delivery_worker',
              }),
            ),
          );
          await _recordFailure(
            message: message,
            error: sent.error,
            commit: commit,
          );
          failed++;
          errors.add(message.id + ':' + sent.error.code);
          continue;
        }

        final successAudit = await auditLogs.append(
          AuditLog(
            id: ids.next('audit'),
            entityType: 'message',
            entityId: message.id,
            action: 'pos_order_pos_sms_succeeded',
            occurredAt: clock.now(),
            payloadJson: jsonEncode({
              'operationId': commit.operationId,
              'destination': body.posDestination,
              'source': 'pos_order_delivery_worker',
            }),
          ),
        );
        if (successAudit is Failure<void>) {
          await _recordFailure(
            message: message,
            error: successAudit.error,
            commit: commit,
          );
          failed++;
          errors.add(message.id + ':' + successAudit.error.code);
          continue;
        }
      }

      await messages.updateStatus(message.id, MessageProcessingStatus.processed);
      await retryService.clearAfterSuccess(message.id);
      delivered++;
    }

    return Success(
      PosOrderDeliveryWorkerReport(
        attempted: attempted,
        delivered: delivered,
        skipped: skipped,
        failed: failed,
        errors: errors,
      ),
    );
  }

  Future<Result<List<IncomingMessage>>> _candidateMessages() async {
    final failed = await messages.listByStatus(MessageProcessingStatus.failed);
    if (failed is Failure<List<IncomingMessage>>) return Failure(failed.error);
    final sending = await messages.listByStatus(MessageProcessingStatus.sending);
    if (sending is Failure<List<IncomingMessage>>) return Failure(sending.error);
    final pending = await messages.listByStatus(MessageProcessingStatus.pending);
    if (pending is Failure<List<IncomingMessage>>) return Failure(pending.error);

    final parsed = await messages.listByStatus(MessageProcessingStatus.parsed);
    if (parsed is Failure<List<IncomingMessage>>) return Failure(parsed.error);

    final map = <String, IncomingMessage>{};
    for (final item in (failed as Success<List<IncomingMessage>>).value) {
      map[item.id] = item;
    }
    for (final item in (sending as Success<List<IncomingMessage>>).value) {
      map[item.id] = item;
    }
    for (final item in (pending as Success<List<IncomingMessage>>).value) {
      map[item.id] = item;
    }
    for (final item in (parsed as Success<List<IncomingMessage>>).value) {
      map[item.id] = item;
    }
    final result = map.values.toList()
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return Success(result);
  }

  Future<Result<_PosOrderCommit?>> _findCommit(String messageId) async {
    final logs = await auditLogs.findByEntity('message', messageId);
    if (logs is Failure<List<AuditLog>>) return Failure(logs.error);
    final entries = (logs as Success<List<AuditLog>>)
        .value
        .where((log) => log.action == 'pos_order_committed')
        .toList(growable: false);
    if (entries.isEmpty) return const Success(null);

    final payload = entries.last.payloadJson ?? '';
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        throw const FormatException('POS order commit is not an object');
      }
      final map = Map<String, Object?>.from(decoded);
      final occurredAt = entries.last.occurredAt;
      final operationId = _requiredString(map, 'operationId');
      final posId = _requiredString(map, 'posId');
      final posName = _requiredString(map, 'posName');
      final customerDestination = _requiredString(map, 'customerDestination');
      final posDestination = _requiredString(map, 'posDestination');
      final categoryName = _requiredString(map, 'categoryName');
      final faceValueMinor = _requiredInt(map, 'faceValueMinor');
      final unitChargeMinor = _requiredInt(map, 'unitChargeMinor');
      final quantity = _requiredInt(map, 'quantity');
      final currencyCode = _requiredString(map, 'currencyCode');
      final rawItems = map['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        throw const FormatException('POS order has no committed items');
      }

      final items = <_PosOrderItem>[];
      for (final raw in rawItems) {
        if (raw is! Map) throw const FormatException('Invalid POS order item');
        final row = Map<String, Object?>.from(raw);
        items.add(
          _PosOrderItem(
            cardId: _requiredString(row, 'cardId'),
            reservationId: _requiredString(row, 'reservationId'),
            saleOperationId: _requiredString(row, 'saleOperationId'),
          ),
        );
      }

      return Success(
        _PosOrderCommit(
          operationId: operationId,
          posId: posId,
          posName: posName,
          customerDestination: customerDestination,
          posDestination: posDestination,
          categoryName: categoryName,
          faceValue: Money(
            minorUnits: faceValueMinor,
            currencyCode: currencyCode,
          ),
          unitCharge: Money(
            minorUnits: unitChargeMinor,
            currencyCode: currencyCode,
          ),
          quantity: quantity,
          items: items,
          occurredAt: occurredAt,
        ),
      );
    } catch (error) {
      return Failure(
        AppFailure(
          code: 'pos_order_commit_state_invalid',
          message: error.toString(),
        ),
      );
    }
  }

  Future<Result<bool>> _hasSuccess(String messageId, String action) async {
    final logs = await auditLogs.findByEntity('message', messageId);
    if (logs is Failure<List<AuditLog>>) return Failure(logs.error);
    return Success(
      (logs as Success<List<AuditLog>>)
          .value
          .any((entry) => entry.action == action),
    );
  }

  Future<Result<bool>> _isDeliveryDue(
    IncomingMessage message,
    _PosOrderCommit commit,
  ) async {
    if (message.status == MessageProcessingStatus.parsed) {
      return const Success(true);
    }
    if (await retryService.isDue(message.id)) {
      return const Success(true);
    }
    final state = await retryService.state(message.id);
    if (state is Failure<MessageRetryState>) return Failure(state.error);
    final retry = (state as Success<MessageRetryState>).value;
    if (message.status == MessageProcessingStatus.failed &&
        retry.attempts == 0 &&
        !retry.exhausted) {
      return const Success(true);
    }
    final timedOut = policy.shouldRequeueAfterConfirmTimeout(
      status: message.status == MessageProcessingStatus.failed
          ? MessageProcessingStatus.sending
          : message.status,
      lastAttemptAt: _commitTime(commit),
      now: clock.now(),
    );
    return Success(timedOut);
  }

  DateTime _commitTime(_PosOrderCommit commit) => commit.occurredAt;

  Future<void> _recordFailure({
    required IncomingMessage message,
    required AppFailure error,
    required _PosOrderCommit commit,
  }) async {
    final result = await retryService.recordFailure(
      messageId: message.id,
      error: error,
    );
    if (result is Failure<MessageRetryState>) return;
    if ((result as Success<MessageRetryState>).value.exhausted) {
      await messages.updateStatus(
        message.id,
        MessageProcessingStatus.failedMaxAttempts,
      );
    } else {
      await messages.updateStatus(message.id, MessageProcessingStatus.failed);
    }
  }

  String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw FormatException('Missing POS order field: ' + key);
  }

  int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is num) return value.toInt();
    throw FormatException('Missing POS order field: ' + key);
  }
}

final class _PosOrderCommit {
  const _PosOrderCommit({
    required this.operationId,
    required this.posId,
    required this.posName,
    required this.customerDestination,
    required this.posDestination,
    required this.categoryName,
    required this.faceValue,
    required this.unitCharge,
    required this.quantity,
    required this.items,
    required this.occurredAt,
  });

  final String operationId;
  final String posId;
  final String posName;
  final String customerDestination;
  final String posDestination;
  final String categoryName;
  final Money faceValue;
  final Money unitCharge;
  final int quantity;
  final List<_PosOrderItem> items;
  final DateTime occurredAt;
}

final class _PosOrderItem {
  const _PosOrderItem({
    required this.cardId,
    required this.reservationId,
    required this.saleOperationId,
  });

  final String cardId;
  final String reservationId;
  final String saleOperationId;
}

final class PosOrderDeliveryWorkerReport {
  const PosOrderDeliveryWorkerReport({
    required this.attempted,
    required this.delivered,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  final int attempted;
  final int delivered;
  final int skipped;
  final int failed;
  final List<String> errors;
}
