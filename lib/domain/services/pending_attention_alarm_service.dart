import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';
import 'local_message_retry_service.dart';

/// تنبيه صوتي/مرئي عند وجود عمليات معلّقة استُنفدت محاولاتها — دليل 1.0.9.
///
/// - مدة قصوى 60 ثانية
/// - كتم يدوي دون مسح البيانات
/// - إيقاف تلقائي عند الخروج للخلفية (عبر [pause])
final class PendingAttentionAlarmService {
  PendingAttentionAlarmService({
    required this.messages,
    required this.retryService,
  });

  final MessageRepository messages;
  final LocalMessageRetryService retryService;

  static const maxAlarmDuration = Duration(seconds: 60);

  bool _muted = false;
  bool _playing = false;
  Timer? _stopTimer;
  Timer? _pollTimer;

  bool get isMuted => _muted;
  bool get isPlaying => _playing;

  void mute() {
    _muted = true;
    _stopPlayback();
  }

  void unmute() => _muted = false;

  /// يوقف الصوت فورًا (مثلاً عند دخول الخلفية) دون تغيير حالة الكتم.
  void pause() => _stopPlayback();

  void startPolling({Duration interval = const Duration(seconds: 15)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => evaluate());
    // فحص فوري
    evaluate();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _stopPlayback();
  }

  Future<int> countExhaustedFailures() async {
    final failed = await messages.listByStatus(MessageProcessingStatus.failed);
    if (failed is! Success<List<IncomingMessage>>) return 0;
    var n = 0;
    for (final m in failed.value) {
      final st = await retryService.state(m.id);
      if (st is Success<MessageRetryState> && st.value.exhausted) {
        n++;
      }
    }
    return n;
  }

  Future<void> evaluate() async {
    if (_muted) return;
    final n = await countExhaustedFailures();
    if (n > 0) {
      _startPlayback();
    } else {
      _stopPlayback();
    }
  }

  void _startPlayback() {
    if (_playing) return;
    _playing = true;
    // اهتزاز + نغمة نظام قصيرة متكررة ضمن مهلة 60ث.
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _stopTimer?.cancel();
    _stopTimer = Timer(maxAlarmDuration, _stopPlayback);
    // نبضات إضافية كل 5 ثوانٍ حتى انتهاء المهلة
    Timer.periodic(const Duration(seconds: 5), (t) {
      if (!_playing) {
        t.cancel();
        return;
      }
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);
    });
  }

  void _stopPlayback() {
    _playing = false;
    _stopTimer?.cancel();
    _stopTimer = null;
  }

  void dispose() {
    stopPolling();
  }
}
