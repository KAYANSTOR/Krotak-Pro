import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM bootstrap for the Android app. It is intentionally opt-in: when the
/// build has no Firebase dart-defines, the existing offline-first app starts
/// normally and this service remains disabled.
final class RemotePushNotificationService {
  RemotePushNotificationService._();
  static final instance = RemotePushNotificationService._();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _started = false;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;

  static bool get isConfigured =>
      const String.fromEnvironment('KROTAK_FIREBASE_API_KEY').isNotEmpty &&
      const String.fromEnvironment('KROTAK_FIREBASE_APP_ID').isNotEmpty &&
      const String.fromEnvironment('KROTAK_FIREBASE_PROJECT_ID').isNotEmpty &&
      const String.fromEnvironment('KROTAK_FIREBASE_MESSAGING_SENDER_ID').isNotEmpty;

  Future<void> start({void Function(RemoteMessage message)? onMessage}) async {
    if (_started || !isConfigured || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: String.fromEnvironment('KROTAK_FIREBASE_API_KEY'),
        appId: String.fromEnvironment('KROTAK_FIREBASE_APP_ID'),
        messagingSenderId: String.fromEnvironment('KROTAK_FIREBASE_MESSAGING_SENDER_ID'),
        projectId: String.fromEnvironment('KROTAK_FIREBASE_PROJECT_ID'),
        storageBucket: String.fromEnvironment('KROTAK_FIREBASE_STORAGE_BUCKET'),
      ),
    );
    await _localNotifications.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_stock'),
    ));
    const channel = AndroidNotificationChannel(
      'krotak_admin',
      'إشعارات الإدارة',
      description: 'إشعارات الإدارة والتنبيهات المركزية',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.subscribeToTopic('krotak_all_users');
    final token = await messaging.getToken();
    if (token != null) _reportToken(token);
    _tokenSubscription = messaging.onTokenRefresh.listen(_reportToken);
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      onMessage?.call(message);
      unawaited(_showForeground(message));
      debugPrint('Krotak remote notification: ${message.messageId}');
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Krotak notification opened: ${message.data}');
      onMessage?.call(message);
    });
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

  void _reportToken(String token) {
    // The token is intentionally not sent to Firestore anonymously. Once the
    // account session is enabled, the authenticated account service should
    // upsert it under users/{uid}/devices/{tokenHash}.
    debugPrint('Krotak FCM token received (${token.length} chars)');
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _foregroundSubscription = null;
    _tokenSubscription = null;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!RemotePushNotificationService.isConfigured) return;
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: String.fromEnvironment('KROTAK_FIREBASE_API_KEY'),
      appId: String.fromEnvironment('KROTAK_FIREBASE_APP_ID'),
      messagingSenderId: String.fromEnvironment('KROTAK_FIREBASE_MESSAGING_SENDER_ID'),
      projectId: String.fromEnvironment('KROTAK_FIREBASE_PROJECT_ID'),
      storageBucket: String.fromEnvironment('KROTAK_FIREBASE_STORAGE_BUCKET'),
    ),
  );
  debugPrint('Krotak background notification: ${message.messageId}');
}
