import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/services/outgoing_dispatch_queue.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late _RecordingSender inner;
  late OutgoingDispatchQueue queue;
  late FixedClock clock;

  setUp(() {
    inner = _RecordingSender();
    clock = FixedClock(DateTime.utc(2026, 9, 21, 11, 0));
    queue = OutgoingDispatchQueue(
      inner: inner,
      clock: clock,
      ids: SequentialIdGenerator(),
    );
  });

  test('financial jobs dispatch before informational ones', () async {
    inner.hold = true;
    final info = queue.enqueue(
      destination: '777000001',
      body: 'ملخص',
      priority: DispatchPriority.informational,
      idempotencyKey: 'info-1',
    );
    final money = queue.enqueue(
      destination: '777000002',
      body: 'كرت 100: ABCD',
      priority: DispatchPriority.financial,
      idempotencyKey: 'fin-1',
    );
    await Future<void>.delayed(Duration.zero);
    inner.release();
    await Future.wait([info, money]);
    expect(inner.destinations, ['777000002', '777000001']);
  });

  test('successful send is idempotent on the same key', () async {
    final first = await queue.enqueue(
      destination: '777111222',
      body: 'تأكيد',
      idempotencyKey: 'sale-9',
    );
    final second = await queue.enqueue(
      destination: '777111222',
      body: 'تأكيد',
      idempotencyKey: 'sale-9',
    );
    expect(first, isA<Success<void>>());
    expect(second, isA<Success<void>>());
    expect(inner.destinations, ['777111222']);
  });

  test('enqueue-to-start stays under the 10 second budget', () async {
    await queue.send(destination: '770000000', body: 'كرت');
    expect(queue.samples, hasLength(1));
    expect(queue.samples.single.meetsTenSecondBudget, isTrue);
    expect(queue.samples.single.enqueueToStart, Duration.zero);
  });

  test('failed send is retried on a later enqueue with same key', () async {
    inner.failNext = true;
    final failed = await queue.enqueue(
      destination: '775555555',
      body: 'كرت',
      idempotencyKey: 'retry-1',
    );
    expect(failed, isA<Failure<void>>());
    inner.failNext = false;
    final again = await queue.enqueue(
      destination: '775555555',
      body: 'كرت',
      idempotencyKey: 'retry-1',
    );
    expect(again, isA<Success<void>>());
    expect(inner.destinations, ['775555555', '775555555']);
  });
}

final class _RecordingSender implements MessageSender {
  final destinations = <String>[];
  bool failNext = false;
  bool hold = false;
  Completer<void>? _gate;

  void release() {
    _gate?.complete();
    _gate = null;
    hold = false;
  }

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    if (hold) {
      _gate ??= Completer<void>();
      await _gate!.future;
    }
    destinations.add(destination);
    if (failNext) {
      failNext = false;
      return const Failure(
        AppFailure(code: 'sms_delivery_failed', message: 'boom'),
      );
    }
    return const Success(null);
  }
}
