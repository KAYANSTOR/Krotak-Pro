import '../core/result.dart';
import '../domain/services/services.dart';
import 'sms_bridge.dart';

final class NativeMessageSender implements MessageSender {
  const NativeMessageSender(this.bridge);

  final SmsBridge bridge;

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    try {
      final receipt = await bridge.sendSms(to: destination, body: body);
      if (!receipt.sent) {
        return const Failure(
          AppFailure(code: 'sms_send_failed', message: 'radio rejected SMS'),
        );
      }
      return const Success(null);
    } catch (e) {
      return Failure(
        AppFailure(code: 'sms_send_failed', message: e.toString()),
      );
    }
  }
}
