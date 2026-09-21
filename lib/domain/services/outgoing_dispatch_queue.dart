import 'dart:async';

import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../repositories/repositories.dart';
import 'services.dart';

/// Priority for SMS dispatch after a financial commit.
///
/// 1. [financial] — voucher / confirmation tied to a committed ledger write.
/// 2. [retry] — resend of an already committed message.
/// 3. [informational] — summaries, balance replies, non-critical notices.
enum DispatchPriority { financial, retry, informational }

/// In-process outgoing SMS queue.
///
/// Does **not** redo ledger work. [send] only dispatches already-prepared
/// text. Duplicate [idempotencyKey] values are skipped after a successful send.
///
/// Latency marks written to the audit log when a repository is provided:
/// `dispatch_enqueued`, `dispatch_started`, `sms_send_result`.
final class OutgoingDispatchQueue implements MessageSender {
  OutgoingDispatchQueue({
    required MessageSender inner,
    required Clock clock,
    required IdGenerator ids,
    AuditLogRepository? auditLogs,
  })  : _inner = inner,
        _clock = clock,
        _ids = ids,
        _auditLogs = auditLogs;

  final MessageSender _inner;
  final Clock _clock;
  final IdGenerator _ids;
  final AuditLogRepository? _auditLogs;

  final List<_Job> _queue = <_Job>[];
  final Set<String> _succeededKeys = <String>{};
  final List<DispatchLatencySample> samples = <DispatchLatencySample>[];
  bool _draining = false;

  int get pendingCount => _queue.length;

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) {
    return enqueue(
      destination: destination,
      body: body,
    );
  }

  Future<Result<void>> enqueue({
    required String destination,
    required String body,
    DispatchPriority priority = DispatchPriority.financial,
    String? idempotencyKey,
    String? correlationId,
  }) async {
    final key = idempotencyKey ?? _defaultKey(destination, body);
    if (_succeededKeys.contains(key)) {
      return const Success(null);
    }
    final job = _Job(
      destination: destination,
      body: body,
      priority: priority,
      idempotencyKey: key,
      correlationId: correlationId ?? key,
      enqueuedAt: _clock.now(),
    );
    _insertByPriority(job);
    _mark(job.correlationId, 'dispatch_enqueued', job.enqueuedAt, {
      'priority': priority.name,
      'destination': destination,
    });
    scheduleMicrotask(() { unawaited(_pump()); });
    return job.result.future;
  }

  Future<void> _pump() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        await _dispatch(job);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _dispatch(_Job job) async {
    if (_succeededKeys.contains(job.idempotencyKey)) {
      job.result.complete(const Success(null));
      return;
    }
    final startedAt = _clock.now();
    _mark(job.correlationId, 'dispatch_started', startedAt, {
      'queueWaitMs':
          startedAt.difference(job.enqueuedAt).inMilliseconds.toString(),
    });
    final sent = await _inner.send(
      destination: job.destination,
      body: job.body,
    );
    final endedAt = _clock.now();
    final ok = sent is Success<void>;
    if (ok) {
      _succeededKeys.add(job.idempotencyKey);
    }
    _mark(job.correlationId, 'sms_send_result', endedAt, {
      'ok': ok.toString(),
      'code': sent is Failure<void> ? sent.error.code : 'ok',
      'dispatchMs': endedAt.difference(startedAt).inMilliseconds.toString(),
      'enqueueToStartMs':
          startedAt.difference(job.enqueuedAt).inMilliseconds.toString(),
    });
    samples.add(
      DispatchLatencySample(
        correlationId: job.correlationId,
        enqueuedAt: job.enqueuedAt,
        dispatchStartedAt: startedAt,
        sendResultAt: endedAt,
        succeeded: ok,
      ),
    );
    job.result.complete(sent);
  }

  void _insertByPriority(_Job job) {
    final rank = job.priority.index;
    var i = 0;
    while (i < _queue.length && _queue[i].priority.index <= rank) {
      i++;
    }
    _queue.insert(i, job);
  }

  String _defaultKey(String destination, String body) =>
      '$destination|${body.hashCode}';

  void _mark(
    String entityId,
    String action,
    DateTime at,
    Map<String, String> fields,
  ) {
    final repo = _auditLogs;
    if (repo == null) return;
    final payload =
        '{${fields.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}';
    unawaited(
      repo.append(
        AuditLog(
          id: _ids.next('dispatch'),
          entityType: 'dispatch',
          entityId: entityId,
          action: action,
          occurredAt: at,
          payloadJson: payload,
        ),
      ),
    );
  }
}

final class DispatchLatencySample {
  const DispatchLatencySample({
    required this.correlationId,
    required this.enqueuedAt,
    required this.dispatchStartedAt,
    required this.sendResultAt,
    required this.succeeded,
  });

  final String correlationId;
  final DateTime enqueuedAt;
  final DateTime dispatchStartedAt;
  final DateTime sendResultAt;
  final bool succeeded;

  Duration get enqueueToStart => dispatchStartedAt.difference(enqueuedAt);
  Duration get startToResult => sendResultAt.difference(dispatchStartedAt);
  Duration get enqueueToResult => sendResultAt.difference(enqueuedAt);

  bool get meetsTenSecondBudget =>
      enqueueToStart < const Duration(seconds: 10);
}

final class _Job {
  _Job({
    required this.destination,
    required this.body,
    required this.priority,
    required this.idempotencyKey,
    required this.correlationId,
    required this.enqueuedAt,
  });

  final String destination;
  final String body;
  final DispatchPriority priority;
  final String idempotencyKey;
  final String correlationId;
  final DateTime enqueuedAt;
  final Completer<Result<void>> result = Completer<Result<void>>();
}
