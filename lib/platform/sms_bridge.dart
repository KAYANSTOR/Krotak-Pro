import 'dart:async';

import 'package:flutter/services.dart';

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
  });

  final String sender;
  final String body;
  final int timestampMillis;

  DateTime get receivedAt =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true);
}
