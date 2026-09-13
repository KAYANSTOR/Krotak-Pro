import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/payment_event.dart';
import 'package:net_app/domain/services/local_notification_parser.dart';

void main() {
  test('notification parser produces notification PaymentEvent without business parsing', () {
    final event = const LocalNotificationParser().parse(
      packageName: 'com.example.wallet',
      sourceKey: 'notification:com.example.wallet',
      title: 'محفظة',
      body: 'تم تحويل 200 ريال الى 777123456 برقم العملية 123',
      receivedAt: DateTime.utc(2026, 9, 13),
    );

    expect(event.channel, PaymentChannel.notification);
    expect(event.packageName, 'com.example.wallet');
    expect(event.sourceKey, 'notification:com.example.wallet');
    expect(event.title, 'محفظة');
    expect(event.body, contains('200'));
  });
}
