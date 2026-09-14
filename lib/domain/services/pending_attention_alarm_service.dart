import 'dart:async';

import 'package:flutter/services.dart';

/// تنبيه صوتي/مرئي عند وجود عمليات معلّقة تحتاج تدخلاً عاجلًا — 1.0.9.
///
/// - حد أقصى 60 ثانية
/// - يتوقف عند الخروج للخلفية (عبر [mute])
/// - زر كتم منفصل دون مسح بيانات الحالة
final class PendingAttentionAlarmService {
  PendingAttentionAlarmService();

  Timer? _timer;
  Timer? _pulse;
  bool _muted = false;
  bool _active = false;
  DateTime? _startedAt;

  static const maxDuration = Duration(seconds: 60);
  static const pulseInterval = Duration(seconds: 2);

  bool get isActive => _active && !_muted;
  bool get isMuted => _muted;

  /// يبدأ التنبيه إن لم يكن مكتومًا. يُعاد تشغيل النبض حتى [maxDuration].
  void start() {
    if (_muted) return;
    _active = true;
    _startedAt = DateTime.now();
    _timer?.cancel();
    _pulse?.cancel();
    _pulse = Timer.periodic(pulseInterval, (_) => _tick());
    _timer = Timer(maxDuration, stop);
    _tick();
  }

  void _tick() {
    if (!_active || _muted) return;
    final started = _startedAt;
    if (started != null && DateTime.now().difference(started) >= maxDuration) {
      stop();
      return;
    }
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  /// كتم الصوت دون مسح أن هناك عناصر معلّقة.
  void mute() {
    _muted = true;
    _pulse?.cancel();
    _pulse = null;
  }

  void unmute() {
    _muted = false;
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _pulse?.cancel();
    _timer = null;
    _pulse = null;
  }

  void dispose() => stop();
}
