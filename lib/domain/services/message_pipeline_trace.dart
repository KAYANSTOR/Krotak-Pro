import 'dart:convert';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../repositories/repositories.dart';

/// Latency instrumentation for the commercial SMS pipeline (plan §6).
///
/// Stages (UTC):
/// - receivedAt
/// - parsedAt
/// - committedAt
/// - dispatchStartedAt
/// - sendResultAt
///
/// Persisted as a single audit action `pipeline_timing` per message so we do
/// not need a schema migration. Safe under offline-first.
final class MessagePipelineTrace {
  MessagePipelineTrace({
    required this.messageId,
    required this.receivedAt,
  });

  final String messageId;
  final DateTime receivedAt;
  DateTime? parsedAt;
  DateTime? committedAt;
  DateTime? dispatchStartedAt;
  DateTime? sendResultAt;
  String? sendOutcome;

  void markParsed([DateTime? at]) => parsedAt = at ?? DateTime.now().toUtc();
  void markCommitted([DateTime? at]) => committedAt = at ?? DateTime.now().toUtc();
  void markDispatchStarted([DateTime? at]) =>
      dispatchStartedAt = at ?? DateTime.now().toUtc();
  void markSendResult({required bool success, DateTime? at}) {
    sendResultAt = at ?? DateTime.now().toUtc();
    sendOutcome = success ? 'success' : 'failure';
  }

  /// Milliseconds from receive → first dispatch attempt (null if not reached).
  int? get receiveToDispatchMs {
    final d = dispatchStartedAt;
    if (d == null) return null;
    return d.difference(receivedAt).inMilliseconds;
  }

  /// Milliseconds from receive → send result (null if not reached).
  int? get receiveToSendResultMs {
    final s = sendResultAt;
    if (s == null) return null;
    return s.difference(receivedAt).inMilliseconds;
  }

  Map<String, Object?> toJson() => {
        'receivedAt': receivedAt.toIso8601String(),
        'parsedAt': parsedAt?.toIso8601String(),
        'committedAt': committedAt?.toIso8601String(),
        'dispatchStartedAt': dispatchStartedAt?.toIso8601String(),
        'sendResultAt': sendResultAt?.toIso8601String(),
        'sendOutcome': sendOutcome,
        'receiveToDispatchMs': receiveToDispatchMs,
        'receiveToSendResultMs': receiveToSendResultMs,
      };
}

/// Writes pipeline timing audits without blocking the financial path on failure.
final class MessagePipelineMetrics {
  const MessagePipelineMetrics({
    required this.auditLogs,
    required this.clock,
    required this.ids,
  });

  final AuditLogRepository auditLogs;
  final Clock clock;
  final IdGenerator ids;

  Future<void> persist(MessagePipelineTrace trace) async {
    try {
      await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'message',
          entityId: trace.messageId,
          action: 'pipeline_timing',
          occurredAt: clock.now(),
          payloadJson: jsonEncode(trace.toJson()),
        ),
      );
    } catch (_) {
      // Metrics must never break commerce.
    }
  }
}
