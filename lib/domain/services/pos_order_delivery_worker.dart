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
import 'pos_order_message_renderer.dart';

// TEMPORARY STUB - being replaced with full content in next commit
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

  Future<Result<PosOrderDeliveryWorkerReport>> tick() async {
    return const Success(PosOrderDeliveryWorkerReport(scanned: 0, delivered: 0, skipped: 0, failed: 0, errors: <String>[]));
  }
}

final class PosOrderDeliveryWorkerReport {
  const PosOrderDeliveryWorkerReport({
    required this.scanned,
    required this.delivered,
    required this.skipped,
    required this.failed,
    required this.errors,
  });
  final int scanned;
  final int delivered;
  final int skipped;
  final int failed;
  final List<String> errors;
}
