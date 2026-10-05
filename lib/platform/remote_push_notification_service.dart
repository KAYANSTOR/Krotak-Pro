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
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _started = false;
  String? _latestToken;
  Future<void> Function(String token)? _tokenWriter;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;

  static bool get isConfigured => true;
  static bool get _hasBuildDefines => const String.fromEnvironment('KROTAK_FIREBASE_API_KEY').isNotEmpty;
  static FirebaseOptions? get _options => _hasBuildDefines
      ? const FirebaseOptions(
          apiKey: String.fromEnvironment('KROTAK_FIREBASE_API_KEY'),
          appId: String.fromEnvironment('KROTAK_FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment('KROTAK_FIREBASE_MESSAGING_SENDER_ID'),
          projectId: String.fromEnvironment('KROTAK_FIREBASE_PROJECT_ID'),
          storageBucket: String.fromEnvironment('KROTAK_FIREBASE_STORAGE_BUCKET'),
        )
      : null;

  /// يربط كاتب الـToken بجلسة الحساب الحالية. إذا وصل الـToken قبل تسجيل
  /// الدخول، يُرسل فور جاهزية الحساب بدل إسقاطه.
  Future<void> bindTokenWriter(Future<void> Function(String token) writer) async {
    _tokenWriter = writer;
    final token = _latestToken;
    if (token != null) await _writeToken(token);
  }

  void unbindTokenWriter() => _tokenWriter = null;

  Future<void> start({void Function(RemoteMessage message)? onMessage}) async {
    if (_started || !isConfigured || defaultTargetPlatform != TargetPlatform.android) return;
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
    await _localNotifications.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_stock'),
    ));
    const channel = AndroidNotificationChannel(
      'krotak_admin',
      'إشعارات الإدارة',
      description: 'إشعارات الإدارة والتنبيهات المركزية',
      importance: Importance.high,
    );
    await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
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
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'krotak_admin',
          'إشعارات الإدارة',
          channelDescription: 'إشعارات الإدارة والتنبيهات المركزية',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_stock',
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

  /// معرف ثابت مشتق من الـToken لتحديث نفس الجهاز عند تغير بياناته.
  static String deviceIdForToken(String token) => base64Url.encode(utf8.encode(token)).replaceAll('=', '');

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
