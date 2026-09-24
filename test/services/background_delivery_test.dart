import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/application/app_container.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide AuditLog, Card, Customer, IncomingMessage, Transaction, TransferTemplate;
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/message.dart';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// إثبات تنفيذي: قسيمة العميل تُسلَّم **والواجهة في الخلفية**.
///
/// كل شيء حقيقي هنا: قاعدة Drift، وحلقة الاسترداد الفعلية (مؤقّت 3 ثوانٍ في
/// `AppContainer`)، وخدمات المجال، وقناة المنصّة التي تحمل SMS فعليًا — تُرصد
/// نداءاتها بنفس الطريقة التي يراها النظام على الجهاز. ما يبقى جهازياً: أن
/// أندرويد لا يقتل العملية فعلًا (وهو ما تمنعه الخدمة الأمامية، ومُختبَر منطقها
/// في DeliveryKeepAlivePolicyTest و delivery_keep_alive_test.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const smsChannel = MethodChannel('com.kayan.net/sms');
  const notificationsChannel = MethodChannel('com.kayan.net/notifications');
  const alertsChannel = MethodChannel('com.kayan.net/alerts');
  const keepAliveChannel = MethodChannel('com.kayan.net/keepalive');

  late AppDatabase database;
  late AppContainer container;
  late List<({String to, String body})> smsSent;
  late List<String> keepAliveCalls;
  late bool smsPermissionsGranted;

  void installPlatformMocks() {
    _messenger.setMockMethodCallHandler(smsChannel, (call) async {
      switch (call.method) {
        case 'hasPermissions':
          return smsPermissionsGranted;
        case 'peekPendingSms':
          return <dynamic>[];
        case 'ackPendingSms':
          return true;
        case 'sendSms':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          smsSent.add((to: args['to'] as String, body: args['body'] as String));
          return <String, dynamic>{
            'sent': true,
            'to': args['to'],
            'requestId': smsSent.length,
          };
      }
      return null;
    });

    // قنوات الأحداث التي يشترك فيها المعالجان عند الإقلاع (بلا بثّ في الاختبار).
    for (final name in const [
      'com.kayan.net/sms_stream',
      'com.kayan.net/notifications_stream',
    ]) {
      _messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }

    _messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      switch (call.method) {
        case 'setAllowedPackages':
        case 'ackPendingNotifications':
        case 'isAccessGranted':
          return true;
        case 'peekPendingNotifications':
          return <dynamic>[];
      }
      return null;
    });

    _messenger.setMockMethodCallHandler(alertsChannel, (call) async {
      if (call.method == 'hasNotificationPermission') return true;
      return true;
    });

    // حالة حقيقية للخدمة: التشغيل ناجح، والحالة تُقرأ من نفس القناة.
    var active = false;
    _messenger.setMockMethodCallHandler(keepAliveChannel, (call) async {
      keepAliveCalls.add(call.method);
      switch (call.method) {
        case 'start':
          active = smsPermissionsGranted;
          return active;
        case 'stop':
          active = false;
          return false;
        case 'status':
          return <String, dynamic>{
            'active': active,
            'smsPermissionsGranted': smsPermissionsGranted,
          };
      }
      return null;
    });
  }

  void removePlatformMocks() {
    for (final name in const [
      'com.kayan.net/sms',
      'com.kayan.net/sms_stream',
      'com.kayan.net/notifications',
      'com.kayan.net/notifications_stream',
      'com.kayan.net/alerts',
      'com.kayan.net/keepalive',
    ]) {
      _messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  }

  /// كرت مُباع وقيد قسيمة معلّق: نفس حالة الإنتاج `voucher_committed` بلا
  /// `sms_delivery_succeeded` — أي قسيمة استحقّها العميل ولم تُرسل بعد.
  Future<void> seedCommittedVoucher() async {
    final now = container.clock.now();
    await container.messages.save(
      IncomingMessage(
        id: 'bg-msg-1',
        sender: 'JAIB',
        body: 'تحويل 100',
        receivedAt: now.subtract(const Duration(minutes: 20)),
        status: MessageProcessingStatus.failed,
      ),
    );
    await container.cards.save(
      const Card(
        id: 'bg-card-1',
        categoryId: 'bg-cat-1',
        serialNumber: 'SN-BG-1',
        secretCode: 'CODE-BG-1',
        status: CardStatus.sold,
      ),
    );
    await container.auditLogs.append(
      AuditLog(
        id: 'bg-audit-1',
        entityType: 'message',
        entityId: 'bg-msg-1',
        action: 'voucher_committed',
        occurredAt: now.subtract(const Duration(minutes: 16)),
        payloadJson: '{"operationId":"bg-op-1","cardId":"bg-card-1",'
            '"categoryId":"bg-cat-1","reservationId":"bg-res-1",'
            '"destination":"733000000"}',
      ),
    );
  }

  /// يقدّم الزمن (دورات الاسترداد كل 3 ثوانٍ) حتى يتحقق الشرط.
  Future<void> advanceUntil(
    WidgetTester tester,
    bool Function() done, {
    int steps = 40,
    Duration step = const Duration(milliseconds: 500),
  }) async {
    for (var i = 0; i < steps && !done(); i++) {
      await tester.pump(step);
    }
  }

  setUp(() async {
    smsSent = <({String to, String body})>[];
    keepAliveCalls = <String>[];
    smsPermissionsGranted = true;
    installPlatformMocks();
    database = AppDatabase(NativeDatabase.memory());
    container = await AppContainer.bootstrap(
      databaseOverride: database,
      backupDirectoryOverride: Directory('test-background-delivery'),
    );
  });

  tearDown(() async {
    // dispose() مكرّر الأمان: الاختبار نفسه يوقفه داخل جسمه حتى لا يبقى مؤقّت
    // الاسترداد معلّقًا (وهو ما يُفشل الاختبار في إطار flutter_test).
    await container.dispose();
    await database.close();
    removePlatformMocks();
  });

  testWidgets(
    'a committed voucher is delivered while the app is backgrounded',
    (tester) async {
      // الإقلاع كالإنتاج: المعالجان + حلقة الاسترداد + طلب خدمة الخلفية.
      await container.startBackgroundHandlers();
      expect(keepAliveCalls, contains('start'));
      expect(container.deliveryKeepAlive.backgroundDeliveryActive, isTrue);
      expect(smsSent, isEmpty);

      // بيع مُلتزم والواجهة ما زالت مفتوحة (قسيمة مستحقة لم تُرسل بعد)،
      // ثم يغادر المستخدم التطبيق.
      await seedCommittedVoucher();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await container.handleAppLifecycle(AppLifecycleState.paused);
      await tester.pump();

      // لا إيقاف لخدمة الخلفية بسبب الخلفية، ولا تسليم قبل دورة الحلقة.
      expect(keepAliveCalls, isNot(contains('stop')));
      expect(smsSent, isEmpty);

      // دورة الاسترداد (3 ثوانٍ) تعمل والواجهة في الخلفية فتسلّم القسيمة.
      await advanceUntil(tester, () => smsSent.isNotEmpty);

      expect(smsSent, hasLength(1));
      expect(smsSent.single.to, '733000000');
      expect(smsSent.single.body, contains('SN-BG-1'));
      expect(smsSent.single.body, contains('CODE-BG-1'));

      final message = await container.messages.findById('bg-msg-1');
      expect(
        (message as Success<IncomingMessage?>).value!.status,
        MessageProcessingStatus.processed,
      );

      // وما زالت الخدمة عاملة بعد التسليم.
      expect(keepAliveCalls, isNot(contains('stop')));
      expect(container.deliveryKeepAlive.backgroundDeliveryActive, isTrue);

      // إيقاف الحلقة قبل نهاية الاختبار (يُطالب إطار الاختبار بلا مؤقتات معلّقة).
      container.stopBackgroundHandlers();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'background cycles deliver a committed voucher exactly once',
    (tester) async {
      await container.startBackgroundHandlers();
      await seedCommittedVoucher();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await container.handleAppLifecycle(AppLifecycleState.paused);

      // عدة دورات استرداد كاملة (10+ ثوانٍ) في الخلفية.
      await advanceUntil(tester, () => smsSent.isNotEmpty);
      await tester.pump(const Duration(seconds: 10));

      expect(smsSent, hasLength(1), reason: 'قسيمة واحدة = إرسال واحد');
      expect(keepAliveCalls, isNot(contains('stop')));

      container.stopBackgroundHandlers();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'revoking sms permissions stops the background service without breaking delivery state',
    (tester) async {
      await container.startBackgroundHandlers();
      keepAliveCalls.clear();

      smsPermissionsGranted = false;
      final status = await container.syncBackgroundDelivery();

      expect(keepAliveCalls, contains('stop'));
      expect(status.active, isFalse);
      expect(container.deliveryKeepAlive.backgroundDeliveryActive, isFalse);

      // العودة إلى المقدمة بعد منح الصلاحية تُعيد التشغيل.
      smsPermissionsGranted = true;
      await container.handleAppLifecycle(AppLifecycleState.resumed);
      expect(keepAliveCalls, contains('start'));
      expect(container.deliveryKeepAlive.backgroundDeliveryActive, isTrue);
      await tester.pump();

      container.stopBackgroundHandlers();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'delivery still runs when the platform keep-alive request is unavailable',
    (tester) async {
      // منصّة لا تدعم الخدمة (أو رفض النظام بدءها): التسليم لا يتوقف.
      _messenger.setMockMethodCallHandler(keepAliveChannel, (call) async {
        throw PlatformException(code: 'foreground_service_not_allowed');
      });

      await container.startBackgroundHandlers();
      await seedCommittedVoucher();
      await container.handleAppLifecycle(AppLifecycleState.paused);
      await advanceUntil(tester, () => smsSent.isNotEmpty);

      expect(smsSent, hasLength(1));
      expect(container.deliveryKeepAlive.backgroundDeliveryActive, isFalse);

      container.stopBackgroundHandlers();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
