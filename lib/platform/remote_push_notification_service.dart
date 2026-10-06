import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// عميل FCM للتطبيق. يعمل اختياريًا فوق التطبيق المحلي ولا يمنع إقلاعه عند
/// فشل الاتصال أو غياب إعداد Firebase.
final class RemotePushNotificationService {
  RemotePushNotificationService._();
  static final instance = RemotePushNotificationService._();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _started = false;
  String? _latestToken;
  Future<void> Function(String token)? _tokenWriter;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;

  /// قناة احترافية جديدة — تغيير المعرف ضروري لأن أندرويد لا يحدّث صوت/أهمية
  /// قناة موجودة مسبقاً.
  static const channelId = 'krotak_admin_v2';
  static const channelName = 'إشعارات الإدارة';
  static const channelDescription = 'إشعارات الإدارة والتنبيهات المركزية — نغمة وأيقونة كروتك برو';

  static bool get isConfigured => true;
  static bool get _hasBuildDefines =>
      const String.fromEnvironment('KROTAK_FIREBASE_API_KEY').isNotEmpty;
  static FirebaseOptions? get _options => _hasBuildDefines
      ? const FirebaseOptions(
          apiKey: String.fromEnvironment('KROTAK_FIREBASE_API_KEY'),
          appId: String.fromEnvironment('KROTAK_FIREBASE_APP_ID'),
          messagingSenderId:
              String.fromEnvironment('KROTAK_FIREBASE_MESSAGING_SENDER_ID'),
          projectId: String.fromEnvironment('KROTAK_FIREBASE_PROJECT_ID'),
          storageBucket:
              String.fromEnvironment('KROTAK_FIREBASE_STORAGE_BUCKET'),
        )
      : null;

  Future<void> bindTokenWriter(Future<void> Function(String token) writer) async {
    _tokenWriter = writer;
    final token = _latestToken;
    if (token != null) await _writeToken(token);
  }

  void unbindTokenWriter() => _tokenWriter = null;

  Future<void> start({void Function(RemoteMessage message)? onMessage}) async {
    if (_started || !isConfigured || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _started = true;
    try {
      await _startInternal(onMessage);
    } catch (error, stackTrace) {
      debugPrint('Krotak remote notifications unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _startInternal(void Function(RemoteMessage message)? onMessage) async {
    final options = _options;
    if (options != null) {
      await Firebase.initializeApp(options: options);
    } else {
      await Firebase.initializeApp();
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // يفتح التطبيق؛ التوجيه تتم معالجته من مسار FCM data.
      },
    );

    final channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('krotak_notify'),
      enableVibration: true,
      showBadge: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.subscribeToTopic('krotak_all_users');
    final token = await messaging.getToken();
    if (token != null) await _reportToken(token);
    _tokenSubscription = messaging.onTokenRefresh.listen(_reportToken);
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      onMessage?.call(message);
      unawaited(_showForeground(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) => onMessage?.call(message));
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) onMessage?.call(initialMessage);
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('krotak_notify'),
          enableVibration: true,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(
            notification.body ?? '',
            contentTitle: notification.title,
            summaryText: 'كروتك برو',
          ),
        ),
      ),
      payload: message.data['route']?.toString(),
    );
  }

  Future<void> _reportToken(String token) async {
    _latestToken = token;
    await _writeToken(token);
  }

  Future<void> _writeToken(String token) async {
    final writer = _tokenWriter;
    if (writer == null) return;
    try {
      await writer(token);
    } catch (error, stackTrace) {
      debugPrint('Krotak FCM token registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static String deviceIdForToken(String token) =>
      base64Url.encode(utf8.encode(token)).replaceAll('=', '');

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _foregroundSubscription = null;
    _tokenSubscription = null;
    _tokenWriter = null;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = RemotePushNotificationService._options;
  if (options != null) {
    await Firebase.initializeApp(options: options);
  } else {
    await Firebase.initializeApp();
  }
  debugPrint('Krotak background notification: ${message.messageId}');
}
