import '../../core/clock.dart';
import '../../core/result.dart';
import '../../platform/system_diagnostics_bridge.dart';
import '../entities/system_capability.dart';

/// خدمة فحص جاهزية النظام — Critical / Recommended / Optional.
final class LocalSystemHealthService {
  LocalSystemHealthService({
    required SystemDiagnosticsBridge bridge,
    required Clock clock,
  })  : _bridge = bridge,
        _clock = clock;

  final SystemDiagnosticsBridge _bridge;
  final Clock _clock;

  Future<Result<SystemHealthSnapshot>> check() async {
    try {
      final probe = await _bridge.probe();
      final caps = _mapProbe(probe);
      return Success(
        SystemHealthSnapshot(capabilities: caps, checkedAt: _clock.now()),
      );
    } catch (e) {
      return Failure(
        AppFailure(code: 'health_check_failed', message: e.toString()),
      );
    }
  }

  Future<Result<SystemHealthSnapshot>> runAction(String settingsAction) async {
    switch (settingsAction) {
      case 'request_sms':
        await _bridge.requestSmsPermissions();
      case 'open_notification_access':
        await _bridge.openNotificationAccess();
      case 'open_battery_optimization':
        await _bridge.openBatteryOptimization();
      case 'open_app_settings':
        await _bridge.openAppSettings();
      case 'open_autostart':
        await _bridge.openAutoStartSettings();
      default:
        break;
    }
    // امنح النظام لحظة لتطبيق الصلاحية ثم أعد الفحص.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return check();
  }

  List<SystemCapability> _mapProbe(Map<String, dynamic> p) {
    CapabilityState boolState(dynamic v) {
      if (v == true) return CapabilityState.granted;
      if (v == false) return CapabilityState.denied;
      return CapabilityState.unknown;
    }

    final sms = boolState(p['smsPermissions']);
    final notif = boolState(p['notificationAccess']);
    final battery = boolState(p['batteryOptimizationIgnored']);
    final dualSim = boolState(p['dualSimReadable']);
    final contacts = boolState(p['contactsPermission']);
    final foreground = boolState(p['canScheduleExactAlarms'] ?? p['foregroundOk']);

    return [
      SystemCapability(
        id: 'sms_read_send',
        title: 'قراءة وإرسال رسائل SMS',
        detail:
            'صلاحية أساسية لاستقبال رسائل المحافظ وإرسال الكروت للعملاء.',
        severity: CapabilitySeverity.critical,
        state: sms,
        actionLabel: sms == CapabilityState.granted ? null : 'منح صلاحية SMS',
        settingsAction: 'request_sms',
      ),
      SystemCapability(
        id: 'foreground_service',
        title: 'تشغيل خدمة الخلفية',
        detail:
            'يضمن استمرار الاستماع للرسائل حتى عند إغلاق الواجهة.',
        severity: CapabilitySeverity.critical,
        state: foreground == CapabilityState.unknown
            ? CapabilityState.granted
            : foreground,
        actionLabel: null,
        settingsAction: 'open_app_settings',
      ),
      SystemCapability(
        id: 'dual_sim',
        title: 'قراءة شرائح الاتصال (Dual SIM)',
        detail: 'التعرف على الشرائح لاختيار شريحة القراءة/الإرسال.',
        severity: CapabilitySeverity.recommended,
        state: dualSim == CapabilityState.unknown
            ? CapabilityState.granted
            : dualSim,
        actionLabel: 'فتح إعدادات التطبيق',
        settingsAction: 'open_app_settings',
      ),
      SystemCapability(
        id: 'battery_optimization',
        title: 'استثناء قيود توفير البطارية',
        detail:
            'منع النظام من إيقاف التطبيق في الخلفية (مهم على Xiaomi/Samsung/Huawei).',
        severity: CapabilitySeverity.recommended,
        state: battery,
        actionLabel: battery == CapabilityState.granted
            ? null
            : 'فتح إعدادات البطارية',
        settingsAction: 'open_battery_optimization',
      ),
      SystemCapability(
        id: 'autostart',
        title: 'التشغيل التلقائي (MIUI / HyperOS / Samsung)',
        detail:
            'السماح بتشغيل التطبيق بعد إعادة التشغيل على واجهات الشركات المصنّعة.',
        severity: CapabilitySeverity.recommended,
        state: CapabilityState.unknown,
        actionLabel: 'فتح إعدادات التشغيل التلقائي',
        settingsAction: 'open_autostart',
      ),
      SystemCapability(
        id: 'contacts',
        title: 'الوصول إلى جهات الاتصال',
        detail: 'اختياري — يساعد على عرض أسماء العملاء من دفتر الهاتف.',
        severity: CapabilitySeverity.optional,
        state: contacts == CapabilityState.unknown
            ? CapabilityState.denied
            : contacts,
        actionLabel: 'فتح إعدادات التطبيق',
        settingsAction: 'open_app_settings',
      ),
      SystemCapability(
        id: 'wallet_notifications',
        title: 'خدمة الاستماع لإشعارات المحافظ',
        detail:
            'التقاط إشعارات جيب/جوالي/كورا/ون كاش وغيرها دون الاعتماد على SMS فقط.',
        severity: CapabilitySeverity.optional,
        state: notif,
        actionLabel: notif == CapabilityState.granted
            ? null
            : 'تفعيل خدمة الإشعارات',
        settingsAction: 'open_notification_access',
      ),
    ];
  }
}
