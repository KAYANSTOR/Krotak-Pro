import 'dart:async';

import 'package:flutter/services.dart';

/// Platform bridge for SMS receive/send on Android.
///
/// Channels:
/// - MethodChannel `com.kayan.net/sms`
/// - EventChannel `com.kayan.net/sms_stream`
class SmsBridge {
  SmsBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ?? const MethodChannel('com.kayan.net/sms'),
        _events = eventChannel ?? const EventChannel('com.kayan.net/sms_stream');

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<IncomingSmsEvent>? _stream;

  Future<bool> hasPermissions() async {
    final result = await _methods.invokeMethod<bool>('hasPermissions');
    return result ?? false;
  }

  Future<bool> requestPermissions() async {
    final result = await _methods.invokeMethod<bool>('requestPermissions');
    return result ?? false;
  }

  Future<void> sendSms({required String to, required String body}) async {
    await _methods.invokeMethod<void>('sendSms', {'to': to, 'body': body});
  }

  /// SMS stored by the Android receiver while Flutter was not listening.
  Future<List<IncomingSmsEvent>> peekPendingSms() async {
    final raw = await _methods.invokeMethod<List<dynamic>>('peekPendingSms');
    if (raw == null) return const [];
    return raw.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return IncomingSmsEvent(
        sender: map['sender'] as String? ?? '',
        body: map['body'] as String? ?? '',
        timestampMillis: (map['timestampMillis'] as num?)?.toInt() ?? 0,
        pendingId: map['id'] as String?,
      );
    }).toList(growable: false);
  }

  Future<void> ackPendingSms(List<String> ids) async {
    if (ids.isEmpty) return;
    await _methods.invokeMethod<void>('ackPendingSms', {'ids': ids});
  }

  Stream<IncomingSmsEvent> get incomingSms {
    return _stream ??= _events.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return IncomingSmsEvent(
        sender: map['sender'] as String? ?? '',
        body: map['body'] as String? ?? '',
        timestampMillis: (map['timestampMillis'] as num?)?.toInt() ?? 0,
      );
    });
  }
}

final class IncomingSmsEvent {
  const IncomingSmsEvent({
    required this.sender,
    required this.body,
    required this.timestampMillis,
    this.pendingId,
  });

  final String sender;
  final String body;
  final int timestampMillis;
  final String? pendingId;

  DateTime get receivedAt =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true);
}
