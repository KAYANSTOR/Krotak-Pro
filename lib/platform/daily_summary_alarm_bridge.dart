import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Schedules the Android alarm that wakes recovery so the existing
/// [LocalPosDailySummaryService.sendDue] can run near local midnight.
///
/// Failures are swallowed: a missing native channel must not block settings.
final class DailySummaryAlarmBridge {
  DailySummaryAlarmBridge({MethodChannel? methods})
      : _methods = methods ?? const MethodChannel('com.kayan.net/alerts');

  final MethodChannel _methods;

  Future<void> setEnabled(bool enabled) async {
    try {
      await _methods.invokeMethod<void>('setDailySummaryAlarm', {
        'enabled': enabled,
      });
    } catch (error) {
      debugPrint('daily summary alarm failed: $error');
    }
  }
}
