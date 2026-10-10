/// WP-9 — تشخيص العمل في الخلفية: أسباب إنهاء العملية وأحداث خدمة الحفاظ.
///
/// المنصّة تُرسل **رموزًا مستقرة فقط**، والنص العربي يُبنى هنا
/// ليُختبر بـDart ولا يتسرّب أي رمز برمجي إلى الواجهة.
library;

/// سبب إنهاء العملية كما يُصنّفه النظام (Android 11+).
enum ProcessExitReasonCode {
  unknown('unknown', 'سبب غير معروف'),
  exitSelf('exit_self', 'إنهاء ذاتي'),
  signaled('signaled', 'إشارة من النظام'),
  lowMemory('low_memory', 'ذاكرة منخفضة'),
  crash('crash', 'انهيار التطبيق'),
  crashNative('crash_native', 'انهيار في الطبقة الأصلية'),
  anr('anr', 'التطبيق لا يستجيب'),
  initializationFailure('initialization_failure', 'فشل التهيئة'),
  permissionChange('permission_change', 'تغيّر صلاحية'),
  excessiveResourceUsage('excessive_resource_usage', 'استهلاك موارد زائد'),
  userRequested('user_requested', 'إغلاق من المستخدم'),
  userStopped('user_stopped', 'إيقاف من المستخدم'),
  dependencyDied('dependency_died', 'انتهاء عملية تابعة'),
  other('other', 'سبب آخر'),
  freezer('freezer', 'تجميد من النظام'),
  packageStateChange('package_state_change', 'تغيّر حالة التطبيق'),
  packageUpdated('package_updated', 'تحديث التطبيق');

  const ProcessExitReasonCode(this.code, this.arabicLabel);

  /// الرمز المنصّي — لا يُعرض للمستخدم أبدًا.
  final String code;
  final String arabicLabel;

  static ProcessExitReasonCode fromCode(Object? code) {
    final text = code?.toString() ?? '';
    for (final value in ProcessExitReasonCode.values) {
      if (value.code == text) return value;
    }
    return ProcessExitReasonCode.unknown;
  }
}

/// حدث خدمة الحفاظ كما يُسجّل في الجهة الأصلية.
enum BackgroundServiceEventCode {
  startRequested('start_requested', 'طُلب تشغيل الخدمة'),
  started('started', 'بدأت خدمة الخلفية'),
  startRejected('start_rejected', 'رفض النظام تشغيل الخدمة'),
  stopped('stopped', 'أُوقفت الخدمة'),
  timeout('timeout', 'انتهت مهلة النوع الأمامي'),
  restartScheduled('restart_scheduled', 'جُدولت إعادة تشغيل'),
  restartAttempted('restart_attempted', 'محاولة إعادة تشغيل مجدولة'),
  bootTrigger('boot_trigger', 'إقلاع الجهاز أو تحديث التطبيق'),
  smsTrigger('sms_trigger', 'وصول رسالة'),
  unknown('unknown', 'حدث غير معروف');

  const BackgroundServiceEventCode(this.code, this.arabicLabel);

  final String code;
  final String arabicLabel;

  static BackgroundServiceEventCode fromCode(Object? code) {
    final text = code?.toString() ?? '';
    for (final value in BackgroundServiceEventCode.values) {
      if (value.code == text) return value;
    }
    return BackgroundServiceEventCode.unknown;
  }
}

/// سبب إنهاء واحد بوقته.
final class ProcessExitReason {
  const ProcessExitReason({
    required this.code,
    required this.at,
    this.description = '',
  });

  final ProcessExitReasonCode code;
  final DateTime at;

  /// وصف من النظام — يُعرض كما هو فقط إن لم يحتو أحرفًا لاتينية.
  final String description;

  static ProcessExitReason? fromMap(Map<Object?, Object?> map) {
    final at = map['timestampMillis'];
    if (at is! num) return null;
    final raw = (map['description'] ?? '').toString().trim();
    return ProcessExitReason(
      code: ProcessExitReasonCode.fromCode(map['code']),
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      description: _isLatin(raw) ? '' : raw,
    );
  }
}

/// حدث خدمة واحد بوقته.
final class BackgroundServiceEvent {
  const BackgroundServiceEvent({
    required this.code,
    required this.at,
    this.detail = '',
  });

  final BackgroundServiceEventCode code;
  final DateTime at;
  final String detail;

  static BackgroundServiceEvent? fromMap(Map<Object?, Object?> map) {
    final at = map['atMillis'];
    if (at is! num) return null;
    final raw = (map['detail'] ?? '').toString().trim();
    return BackgroundServiceEvent(
      code: BackgroundServiceEventCode.fromCode(map['event']),
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      detail: _isLatin(raw) ? '' : raw,
    );
  }
}

/// لقطة تشخيص الخلفية المعروضة في شاشة التحقق من الجهاز.
final class BackgroundDiagnostics {
  const BackgroundDiagnostics({
    this.exitReasons = const <ProcessExitReason>[],
    this.serviceEvents = const <BackgroundServiceEvent>[],
    this.targetSdk,
  });

  final List<ProcessExitReason> exitReasons;
  final List<BackgroundServiceEvent> serviceEvents;
  final int? targetSdk;

  bool get isEmpty => exitReasons.isEmpty && serviceEvents.isEmpty;

  static BackgroundDiagnostics fromPayload({
    required List<Object?> exitReasons,
    required List<Object?> serviceEvents,
    int? targetSdk,
  }) {
    return BackgroundDiagnostics(
      exitReasons: exitReasons
          .whereType<Map<Object?, Object?>>()
          .map(ProcessExitReason.fromMap)
          .whereType<ProcessExitReason>()
          .toList(growable: false),
      serviceEvents: serviceEvents
          .whereType<Map<Object?, Object?>>()
          .map(BackgroundServiceEvent.fromMap)
          .whereType<BackgroundServiceEvent>()
          .toList(growable: false),
      targetSdk: targetSdk,
    );
  }
}

/// يكشف أي حرف لاتيني في نص النظام حتى لا يتسرّب إلى الواجهة.
bool _isLatin(String text) => RegExp('[A-Za-z]').hasMatch(text);
