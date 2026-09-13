import 'dart:async';
import 'package:flutter/services.dart';

final class NotificationBridge {
  NotificationBridge({MethodChannel? methods, EventChannel? events})
      : _methods = methods ?? const MethodChannel('com.kayan.net/notifications'),
        _events = events ?? const EventChannel('com.kayan.net/notifications_stream');
  final MethodChannel _methods;
  final EventChannel _events;
  Stream<IncomingNotificationEvent>? _stream;

  Future<bool> isAccessGranted() async => await _methods.invokeMethod<bool>('isAccessGranted') ?? false;
  Future<void> openAccessSettings() => _methods.invokeMethod<void>('openAccessSettings');

  Future<void> setAllowedPackages(Iterable<String> packages) =>
      _methods.invokeMethod<void>('setAllowedPackages', {'packages': packages.toList(growable: false)});

  Future<List<IncomingNotificationEvent>> peekPending() async {
    final raw = await _methods.invokeMethod<List<dynamic>>('peekPendingNotifications') ?? const [];
    return raw.map((item) => IncomingNotificationEvent.fromMap(Map<String, dynamic>.from(item as Map))).toList(growable: false);
  }

  Future<void> ackPending(Iterable<String> ids) =>
      _methods.invokeMethod<void>('ackPendingNotifications', {'ids': ids.toList(growable: false)});

  Stream<IncomingNotificationEvent> get incomingNotifications => _stream ??= _events.receiveBroadcastStream().map(
        (event) => IncomingNotificationEvent.fromMap(Map<String, dynamic>.from(event as Map)),
      );
}

final class IncomingNotificationEvent {
  const IncomingNotificationEvent({required this.id, required this.packageName, required this.body, required this.receivedAt, this.title});
  final String id;
  final String packageName;
  final String body;
  final String? title;
  final DateTime receivedAt;

  factory IncomingNotificationEvent.fromMap(Map<String, dynamic> map) {
    return IncomingNotificationEvent(
      id: map['id'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      body: map['body'] as String? ?? '',
      title: map['title'] as String?,
      receivedAt: DateTime.fromMillisecondsSinceEpoch((map['timestampMillis'] as num?)?.toInt() ?? 0, isUtc: true),
    );
  }
}
