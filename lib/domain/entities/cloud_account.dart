import '../../core/cloud_config.dart';

/// حساب الشبكة كما هو محفوظ في Firestore — نفس الوثيقة التي تقرأها لوحة الإدارة.
final class CloudAccount {
  const CloudAccount({
    required this.uid,
    required this.phone,
    required this.networkName,
    required this.isTrial,
    required this.isActive,
    this.subscriptionEnd,
    this.warningMessage = '',
    this.hasCustomWarning = false,
    this.commissionRate,
    this.createdAt,
    this.lastSeenAt,
  });

  final String uid;
  final String phone;
  final String networkName;
  final bool isTrial;
  final bool isActive;
  final DateTime? subscriptionEnd;
  final String warningMessage;
  final bool hasCustomWarning;
  final double? commissionRate;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  bool get isBlocked => !isActive;

  bool get isExpired =>
      subscriptionEnd != null && subscriptionEnd!.isBefore(DateTime.now());

  /// الأيام المتبقية حتى انتهاء التجربة/الاشتراك (سالب إذا انتهى).
  int? get remainingDays {
    final end = subscriptionEnd;
    if (end == null) return null;
    return end.difference(DateTime.now()).inHours ~/ 24;
  }

  String get statusLabel {
    if (!isActive) return 'موقوف';
    if (isTrial) return 'تجريبي';
    return 'رسمي';
  }

  static CloudAccount? fromMap(String uid, Map<String, dynamic> data) {
    final phone = data['phone']?.toString();
    if (phone == null || phone.isEmpty) {
      // حساب بلا رقم هاتف لا يمكن التحقق من ملكيته — يُعامل كغير صالح.
      return null;
    }
    return CloudAccount(
      uid: uid,
      phone: phone,
      networkName: data['network_name']?.toString() ?? '',
      isTrial: data['is_trial'] != false,
      isActive: data['is_active'] != false,
      subscriptionEnd: _asDate(data['subscription_end_date']),
      warningMessage: data['warning_message']?.toString() ?? '',
      hasCustomWarning: data['has_custom_warning'] == true,
      commissionRate: _asDouble(data['commission_rate']),
      createdAt: _asDate(data['created_at']),
      lastSeenAt: _asDate(data['last_seen_at']),
    );
  }

  static DateTime? _asDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static double? _asDouble(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
}

/// إشعار يصل من الإدارة (عام أو لحساب محدد).
final class CloudNotification {
  const CloudNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    required this.isGlobal,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final bool isGlobal;

  CloudNotification copyWith({bool? isRead}) => CloudNotification(
        id: id,
        title: title,
        message: message,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        isGlobal: isGlobal,
      );

  static CloudNotification? fromMap(
    Map<String, dynamic> data, {
    required bool isGlobal,
  }) {
    final title = data['title']?.toString() ?? '';
    final message = data['message']?.toString() ?? '';
    if (title.isEmpty && message.isEmpty) return null;
    final rawTimestamp = data['timestamp'] ?? data['created_at'];
    DateTime createdAt;
    if (rawTimestamp is DateTime) {
      createdAt = rawTimestamp;
    } else if (rawTimestamp is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
    } else if (rawTimestamp is num) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawTimestamp.toInt());
    } else {
      createdAt = DateTime.tryParse(rawTimestamp?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return CloudNotification(
      id: data['__id']?.toString() ?? data['id']?.toString() ?? '',
      title: title,
      message: message,
      createdAt: createdAt,
      isRead: data['is_read'] == true,
      isGlobal: isGlobal,
    );
  }
}

/// الإعداد العام للتطبيق — `app_settings/global_config` (نفس وثيقة لوحة الإدارة).
final class CloudGlobalConfig {
  const CloudGlobalConfig({
    this.isAppActive = true,
    this.maintenanceMessage = '',
    this.defaultTrialDays = CloudConfig.fallbackTrialDays,
    this.defaultTrialWarning = '',
    this.globalOfficialWarning = '',
    this.warningDaysBeforeExpiry = 5,
    this.defaultCommissionRate = 5,
  });

  final bool isAppActive;
  final String maintenanceMessage;
  final int defaultTrialDays;
  final String defaultTrialWarning;
  final String globalOfficialWarning;
  final int warningDaysBeforeExpiry;

  /// نسبة العمولة العامة من لوحة الإدارة (`default_commission_rate`).
  final double defaultCommissionRate;

  static CloudGlobalConfig fromMap(Map<String, dynamic>? data) {
    if (data == null) return const CloudGlobalConfig();
    final trialDays = data['default_trial_days'];
    final parsedTrialDays = trialDays is num
        ? trialDays.toInt()
        : int.tryParse(trialDays?.toString() ?? '');
    final commissionRaw = data['default_commission_rate'];
    final commission = commissionRaw is num
        ? commissionRaw.toDouble()
        : double.tryParse(commissionRaw?.toString() ?? '') ?? 5;
    return CloudGlobalConfig(
      isAppActive: data['is_app_active'] != false,
      maintenanceMessage: data['maintenance_message']?.toString() ?? '',
      defaultTrialDays: (parsedTrialDays ?? CloudConfig.fallbackTrialDays)
          .clamp(0, CloudConfig.maxTrialDays),
      defaultTrialWarning: data['default_trial_warning']?.toString() ?? '',
      globalOfficialWarning: data['global_official_warning']?.toString() ?? '',
      warningDaysBeforeExpiry:
          int.tryParse(data['warning_days_before_expiry']?.toString() ?? '') ?? 5,
      defaultCommissionRate: commission > 0 ? commission : 5,
    );
  }
}
