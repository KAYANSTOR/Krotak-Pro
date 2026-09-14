/// تصنيف إمكانيات جاهزية النظام — مطابق دليل 1.0.9.
enum CapabilitySeverity { critical, recommended, optional }

enum CapabilityState { granted, denied, unknown, unavailable }

final class SystemCapability {
  const SystemCapability({
    required this.id,
    required this.title,
    required this.detail,
    required this.severity,
    required this.state,
    this.actionLabel,
    this.settingsAction,
  });

  final String id;
  final String title;
  final String detail;
  final CapabilitySeverity severity;
  final CapabilityState state;

  /// نص الزر (مثل: منح الصلاحية / فتح الإعدادات).
  final String? actionLabel;

  /// مفتاح إجراء المنصة: request_sms | open_notification_access |
  /// open_battery_optimization | open_app_settings | open_sim_settings
  final String? settingsAction;

  bool get isOk => state == CapabilityState.granted;
  bool get isBlocking => severity == CapabilitySeverity.critical && !isOk;

  SystemCapability copyWith({CapabilityState? state}) => SystemCapability(
        id: id,
        title: title,
        detail: detail,
        severity: severity,
        state: state ?? this.state,
        actionLabel: actionLabel,
        settingsAction: settingsAction,
      );
}

enum SystemHealthLevel { ready, warning, critical }

final class SystemHealthSnapshot {
  const SystemHealthSnapshot({
    required this.capabilities,
    required this.checkedAt,
  });

  final List<SystemCapability> capabilities;
  final DateTime checkedAt;

  List<SystemCapability> of(CapabilitySeverity s) =>
      capabilities.where((c) => c.severity == s).toList(growable: false);

  int get criticalFailCount =>
      capabilities.where((c) => c.isBlocking).length;

  int get recommendedFailCount => capabilities
      .where(
        (c) =>
            c.severity == CapabilitySeverity.recommended && !c.isOk,
      )
      .length;

  SystemHealthLevel get level {
    if (criticalFailCount > 0) return SystemHealthLevel.critical;
    if (recommendedFailCount > 0) return SystemHealthLevel.warning;
    return SystemHealthLevel.ready;
  }

  String get bannerMessage {
    switch (level) {
      case SystemHealthLevel.ready:
        return 'النظام جاهز — الصلاحيات والخدمات تعمل بشكل سليم';
      case SystemHealthLevel.warning:
        return 'تحذير جاهزية: $recommendedFailCount إعداد مستحسن غير مفعّل';
      case SystemHealthLevel.critical:
        return 'خلل حرج: $criticalFailCount صلاحية أساسية غير مفعّلة — الأتمتة متوقفة أو ناقصة';
    }
  }
}
