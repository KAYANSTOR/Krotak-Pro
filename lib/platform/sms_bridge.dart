import 'dart:async';

import 'package:flutter/services.dart';

/// Platform bridge for SMS receive/send on Android.
///
/// Channels:
/// - MethodChannel `com.kayan.net/sms`
/// - EventChannel `com.kayan.net/sms_stream`
/// - EventChannel `com.kayan.net/sms_outbound` (carrier delivery reports)
class SmsBridge {
  SmsBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    EventChannel? outboundEventChannel,
  })  : _methods = methodChannel ?? const MethodChannel('com.kayan.net/sms'),
        _events = eventChannel ?? const EventChannel('com.kayan.net/sms_stream'),
        _outboundEvents = outboundEventChannel ??
            const EventChannel('com.kayan.net/sms_outbound');

  final MethodChannel _methods;
  final EventChannel _events;
  final EventChannel _outboundEvents;

  Stream<IncomingSmsEvent>? _stream;
  Stream<SmsDeliveryEvent>? _outboundStream;

  Future<bool> hasPermissions() async {
    final result = await _methods.invokeMethod<bool>('hasPermissions');
    return result ?? false;
  }

  Future<bool> requestPermissions() async {
    final result = await _methods.invokeMethod<bool>('requestPermissions');
    return result ?? false;
  }

  /// Hands the SMS to the radio and waits for the *sent* PendingIntent.
  ///
  /// Carrier *delivery* is reported later on [outboundEvents].
  Future<SmsSendReceipt> sendSms({
    required String to,
    required String body,
  }) async {
    final raw = await _methods.invokeMethod<dynamic>('sendSms', {
      'to': to,
      'body': body,
    });
    return SmsSendReceipt.fromPlatform(raw, fallbackTo: to);
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

  Stream<SmsDeliveryEvent> get outboundEvents {
    return _outboundStream ??=
        _outboundEvents.receiveBroadcastStream().map(SmsDeliveryEvent.fromPlatform);
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

final class SmsSendReceipt {
  const SmsSendReceipt({
    required this.sent,
    required this.to,
    this.requestId,
  });

  final bool sent;
  final String to;
  final int? requestId;

  static SmsSendReceipt fromPlatform(Object? raw, {required String fallbackTo}) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      return SmsSendReceipt(
        sent: map['sent'] == true || map['sent'] == 'true',
        to: map['to'] as String? ?? fallbackTo,
        requestId: (map['requestId'] as num?)?.toInt(),
      );
    }
    return SmsSendReceipt(sent: raw != false, to: fallbackTo);
  }
}

final class SmsDeliveryEvent {
  const SmsDeliveryEvent({
    required this.requestId,
    required this.to,
    required this.delivered,
    required this.resultCode,
  });

  final int requestId;
  final String to;
  final bool delivered;
  final int resultCode;

  static SmsDeliveryEvent fromPlatform(Object? raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return SmsDeliveryEvent(
      requestId: (map['requestId'] as num?)?.toInt() ?? 0,
      to: map['to'] as String? ?? '',
      delivered: map['delivered'] == true || map['delivered'] == 'true',
      resultCode: (map['resultCode'] as num?)?.toInt() ?? -1,
    );
  }
}
