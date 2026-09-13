import 'dart:async';

import '../core/result.dart';
import '../domain/entities/payment_event.dart';
import '../domain/services/local_notification_parser.dart';
import '../domain/services/local_payment_source_registry.dart';
import '../domain/services/unified_payment_event_engine.dart';
import '../platform/notification_bridge.dart';

final class IncomingNotificationHandler {
  IncomingNotificationHandler({required this.bridge, required this.sources, required this.engine, this.parser = const LocalNotificationParser()});
  final NotificationBridge bridge;
  final LocalPaymentSourceRegistry sources;
  final UnifiedPaymentEventEngine engine;
  final LocalNotificationParser parser;
  StreamSubscription<IncomingNotificationEvent>? _subscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _syncPackages();
    _subscription ??= bridge.incomingNotifications.listen(_handle);
    await drainPending();
  }

  Future<void> drainPending() async {
    for (final event in await bridge.peekPending()) {
      await _handle(event);
    }
  }

  Future<void> _handle(IncomingNotificationEvent event) async {
    final result = await sources.list();
    if (result is Failure) return;
    final configured = (result as Success<List<PaymentSource>>).value.where((s) => s.packageName == event.packageName).firstOrNull;
    if (configured == null || !configured.enabled || configured.packageName == null) return;

    final ingest = await engine.ingest(
      parser.parse(
        packageName: event.packageName,
        sourceKey: configured.id,
        body: event.body,
        receivedAt: event.receivedAt,
        title: event.title,
      ),
    );

    if (ingest is Success) {
      await bridge.ackPending([event.id]);
      return;
    }

    final failure = (ingest as Failure).error;
    // Transport ACK is forbidden when the unified engine failed before the
    // inbound message was durably persisted. Keeping the platform event in
    // the encrypted queue allows the next recovery cycle to retry safely.
    const unsafeToAck = {
      'message_reference_find_failed',
      'message_save_failed',
    };
    if (!unsafeToAck.contains(failure.code)) {
      // From this point failures are expected to be represented by the local
      // IncomingMessage (failed/rejected/parsed) and can be recovered/reviewed.
      await bridge.ackPending([event.id]);
    }
  }

  Future<void> _syncPackages() async {
    final result = await sources.list();
    if (result is Failure) return;
    final packages = (result as Success<List<PaymentSource>>).value
        .where((s) => s.enabled && s.packageName != null)
        .map((s) => s.packageName!)
        .toSet();
    await bridge.setAllowedPackages(packages);
  }

  Future<void> refreshSources() => _syncPackages();

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
