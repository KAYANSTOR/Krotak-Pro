import '../entities/message.dart';

/// Storage contract for the atomic outbound-dispatch claim.
///
/// The implementation must transition a dispatchable row to `sending` in one
/// conditional database update. A read followed by a write is not sufficient.
abstract interface class OutboundMessageStore {
  Future<bool> claimForDispatch(
    String messageId, {
    required DateTime now,
    required DateTime staleBefore,
  });
}

/// Prevents two recovery/worker passes from sending the same prepared message.
///
/// The actual SMS operation remains owned by the existing caller; this guard
/// only performs the atomic claim and invokes it after a successful claim.
final class OutboundMessageDispatchGuard {
  const OutboundMessageDispatchGuard({required this.store});

  final OutboundMessageStore store;

  Future<bool> runOnce(
    IncomingMessage message,
    Future<void> Function() sendSms, {
    DateTime? now,
    Duration staleAfter = const Duration(minutes: 15),
  }) async {
    final claimed = await store.claimForDispatch(
      message.id,
      now: now ?? DateTime.now(),
      staleBefore: (now ?? DateTime.now()).subtract(staleAfter),
    );
    if (!claimed) return false;
    await sendSms();
    return true;
  }
}
