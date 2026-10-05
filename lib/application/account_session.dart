import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/app_brand.dart';
import '../core/clock.dart';
import '../core/cloud_config.dart';
import '../core/result.dart';
import '../data/cloud/cloud_http.dart';
import '../data/cloud/firebase_rest_client.dart';
import '../domain/entities/cloud_account.dart';
import '../domain/entities/setting.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/cloud_account_service.dart';
import '../domain/services/cloud_commission_service.dart';
import '../platform/remote_push_notification_service.dart';

/// مراحل حالة الحساب في التطبيق.
enum AccountPhase {
  loading,
  unconfigured,
  signedOut,
  blocked,
  ready,
}

@immutable
final class AccountState {
  const AccountState({
    required this.phase,
    this.account,
    this.session,
    this.config = const CloudGlobalConfig(),
    this.notifications = const <CloudNotification>[],
    this.message = '',
    this.offline = false,
  });

  final AccountPhase phase;
  final CloudAccount? account;
  final CloudSession? session;
  final CloudGlobalConfig config;
  final List<CloudNotification> notifications;
  final String message;
  final bool offline;

  int get unreadCount =>
      notifications.where((notification) => !notification.isRead).length;

  AccountState copyWith({
    AccountPhase? phase,
    CloudAccount? account,
    CloudSession? session,
    CloudGlobalConfig? config,
    List<CloudNotification>? notifications,
    String? message,
    bool? offline,
  }) =>
      AccountState(
        phase: phase ?? this.phase,
        account: account ?? this.account,
        session: session ?? this.session,
        config: config ?? this.config,
        notifications: notifications ?? this.notifications,
        message: message ?? this.message,
        offline: offline ?? this.offline,
      );
}

/// جلسة الحساب: تحفظ الرموز محلياً، تزامن الحالة مع الإدارة.
final class AccountSession {
  AccountSession({
    required SettingsRepository settings,
    Clock clock = const SystemClock(),
    CloudAccountService? service,
    SaleRepository? sales,
  })  : _settings = settings,
        _clock = clock,
        _service = service ?? CloudAccountService(),
        _sales = sales;

  static AccountSession? _instance;
  static AccountSession get instance {
    final current = _instance;
    if (current == null) {
      throw StateError('AccountSession لم تُهيَّأ بعد.');
    }
    return current;
  }

  static void attach(AccountSession session) => _instance = session;
  static AccountSession? get maybeInstance => _instance;

  final SettingsRepository _settings;
  final Clock _clock;
  final CloudAccountService _service;
  final SaleRepository? _sales;

  final ValueNotifier<AccountState> state =
      ValueNotifier<AccountState>(const AccountState(phase: AccountPhase.loading));

  Timer? _syncTimer;
  bool _syncing = false;
  DateTime? _lastPresenceAt;

  bool get isConfigured => _service.isConfigured;

  /// مسار سريع بدون نت: يعرض الحالة المحفوظة فوراً ثم يزامن بمهلة قصيرة.
  Future<void> initialize() async {
    if (!_service.isConfigured) {
      state.value = const AccountState(phase: AccountPhase.unconfigured);
      return;
    }

    final uid = await _read(SettingKeys.cloudAccountUid);
    final refreshToken = await _read(SettingKeys.cloudRefreshToken);
    if (uid == null || uid.isEmpty || refreshToken == null || refreshToken.isEmpty) {
      state.value = const AccountState(phase: AccountPhase.signedOut);
      return;
    }

    final hadCache = await _restoreCachedState(offline: true);
    if (!hadCache) {
      state.value = const AccountState(phase: AccountPhase.loading);
    }

    try {
      final session = await _service
          .restoreSession(uid: uid, refreshToken: refreshToken)
          .timeout(CloudConfig.bootNetworkTimeout);
      await _persistSession(session);
      final account = await _service
          .fetchAccount(uid, idToken: session.idToken)
          .timeout(CloudConfig.bootNetworkTimeout);
      if (account == null) {
        await signOut();
        return;
      }
      await _applyAccount(account, session);
    } on TimeoutException {
      if (!hadCache) await _restoreCachedState(offline: true);
    } on CloudHttpException catch (error) {
      if (error.isNetworkFailure) {
        if (!hadCache) await _restoreCachedState(offline: true);
        return;
      }
      if (!hadCache) await signOut();
    }
  }

  Future<bool> _restoreCachedState({required bool offline}) async {
    final cached = await _cachedAccount();
    if (cached == null) {
      if (state.value.phase == AccountPhase.loading) {
        state.value = const AccountState(phase: AccountPhase.signedOut);
      }
      return false;
    }
    final trialWarning = await _read(SettingKeys.cloudTrialWarning) ?? '';
    state.value = AccountState(
      phase: cached.isBlocked ? AccountPhase.blocked : AccountPhase.ready,
      account: cached,
      message: cached.warningMessage.isNotEmpty ? cached.warningMessage : trialWarning,
      offline: offline,
    );
    return true;
  }

  Future<void> register({
    required String networkName,
    required String phone,
    required String password,
  }) async {
    _service.ensureConfigured();
    final session = await _service.register(
      networkName: networkName,
      phone: phone,
      password: password,
    );
    await _persistSession(session);
    final account = await _service.fetchAccount(
      session.uid,
      idToken: session.idToken,
    );
    if (account == null) {
      throw const CloudHttpException(
        statusCode: 0,
        code: 'account_missing',
        message: 'تم إنشاء الحساب لكن تعذّر تحميل بياناته. أعد المحاولة.',
      );
    }
    await _applyAccount(account, session);
  }

  Future<void> signIn({
    required String phone,
    required String password,
  }) async {
    _service.ensureConfigured();
    final session = await _service.signIn(phone: phone, password: password);
    final account = await _service.fetchAccount(
      session.uid,
      idToken: session.idToken,
    );
    if (account == null) {
      await _service.touchPresence(uid: session.uid, idToken: session.idToken);
      throw const CloudHttpException(
        statusCode: 404,
        code: 'account_missing',
        message:
            'لا توجد بيانات حساب لهذا الرقم. تواصل مع الإدارة لتفعيل حسابك.',
      );
    }
    await _persistSession(session);
    await _applyAccount(account, session);
  }

  Future<void> signOut() async {
    _stopTimer();
    RemotePushNotificationService.instance.unbindTokenWriter();
    await _clear(SettingKeys.cloudAccountUid);
    await _clear(SettingKeys.cloudRefreshToken);
    await _clear(SettingKeys.cloudPhone);
    await _clear(SettingKeys.cloudNetworkName);
    await _clear(SettingKeys.cloudIsTrial);
    await _clear(SettingKeys.cloudIsActive);
    await _clear(SettingKeys.cloudSubscriptionEnd);
    await _clear(SettingKeys.cloudTrialWarning);
    await _clear(SettingKeys.cloudGlobalSeenAt);
    state.value = const AccountState(phase: AccountPhase.signedOut);
  }

  Future<void> sync({bool force = false}) async {
    if (!_service.isConfigured) return;
    if (_syncing && !force) return;

    final current = state.value;
    var session = current.session;
    final uid = current.account?.uid ??
        await _read(SettingKeys.cloudAccountUid) ??
        '';
    if (uid.isEmpty) return;

    _syncing = true;
    try {
      if (session == null || session.isExpired) {
        final refreshToken = await _read(SettingKeys.cloudRefreshToken);
        if (refreshToken == null || refreshToken.isEmpty) return;
        session = await _service.restoreSession(uid: uid, refreshToken: refreshToken);
        await _persistSession(session);
      }

      final account = await _service.fetchAccount(uid, idToken: session.idToken);
      if (account == null) {
        await signOut();
        return;
      }

      await _applyAccount(account, session, syncNotifications: true);

      final now = _clock.now();
      final lastPresence = _lastPresenceAt;
      if (lastPresence == null ||
          now.difference(lastPresence) >= CloudConfig.presenceInterval) {
        _lastPresenceAt = now;
        await _service.touchPresence(uid: uid, idToken: session.idToken);
      }
    } on CloudHttpException catch (error) {
      if (error.isNetworkFailure) {
        state.value = state.value.copyWith(offline: true);
      } else if (error.statusCode == 401 || error.code == 'UNAUTHENTICATED') {
        await signOut();
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> refreshNotifications() async {
    final current = state.value;
    final session = current.session;
    final uid = current.account?.uid;
    if (session == null || uid == null) return;
    try {
      final notifications = await _collectNotifications(uid, session.idToken);
      state.value = current.copyWith(notifications: notifications, offline: false);
    } on CloudHttpException catch (error) {
      if (error.isNetworkFailure) {
        state.value = current.copyWith(offline: true);
      }
    }
  }

  Future<void> markNotificationRead(CloudNotification notification) async {
    final current = state.value;
    final session = current.session;
    final uid = current.account?.uid;
    if (session == null || uid == null) return;

    if (notification.isGlobal) {
      await _write(
        SettingKeys.cloudGlobalSeenAt,
        _clock.now().toIso8601String(),
      );
    } else {
      try {
        await _service.markNotificationRead(
          uid: uid,
          notificationId: notification.id,
          idToken: session.idToken,
        );
      } on CloudHttpException {
        // ignore
      }
    }

    final updated = current.notifications
        .map((item) => item.id == notification.id
            ? item.copyWith(isRead: true)
            : item)
        .toList(growable: false);
    state.value = current.copyWith(notifications: updated);
  }

  Future<void> markAllNotificationsRead() async {
    final current = state.value;
    final unread = current.notifications
        .where((notification) => !notification.isRead)
        .toList(growable: false);
    if (unread.isEmpty) return;
    for (final notification in unread) {
      await markNotificationRead(notification);
    }
  }

  Future<void> _applyAccount(
    CloudAccount account,
    CloudSession session, {
    bool syncNotifications = true,
  }) async {
    final config = await _service.fetchGlobalConfig(session.idToken);

    var notifications = state.value.notifications;
    if (syncNotifications) {
      try {
        notifications = await _collectNotifications(account.uid, session.idToken);
      } on CloudHttpException {
        // keep previous
      }
    }

    await _write(SettingKeys.cloudAccountUid, account.uid);
    await _write(SettingKeys.cloudPhone, account.phone);
    await _write(SettingKeys.cloudIsTrial, account.isTrial.toString());
    await _write(SettingKeys.cloudIsActive, account.isActive.toString());
    if (account.subscriptionEnd != null) {
      await _write(
        SettingKeys.cloudSubscriptionEnd,
        account.subscriptionEnd!.toIso8601String(),
      );
    }
    if (account.networkName.isNotEmpty) {
      await _write(SettingKeys.cloudNetworkName, account.networkName);
      await _settings.save(
        AppSetting(
          key: SettingKeys.networkName,
          value: account.networkName,
          updatedAt: _clock.now(),
        ),
      );
    }

    final message = _statusMessage(account, config);
    await _write(SettingKeys.cloudTrialWarning, message);

    final blocked = account.isBlocked || !config.isAppActive;
    state.value = AccountState(
      phase: blocked ? AccountPhase.blocked : AccountPhase.ready,
      account: account,
      session: session,
      config: config,
      notifications: notifications,
      message: message,
      offline: false,
    );

    if (!blocked) {
      _startTimer();
      unawaited(RemotePushNotificationService.instance.bindTokenWriter((token) {
        return _service.upsertDeviceToken(
          uid: account.uid,
          token: token,
          deviceId: RemotePushNotificationService.deviceIdForToken(token),
          idToken: session.idToken,
        );
      }));
      // مزامنة مبيعات الشهر مع لوحة الإدارة لحساب العمولات.
      final salesRepo = _sales;
      if (salesRepo != null) {
        unawaited(
          CloudCommissionService(sales: salesRepo, cloud: _service).syncCompletedSales(
            uid: account.uid,
            idToken: session.idToken,
          ),
        );
      }
    }
  }

  String _statusMessage(CloudAccount account, CloudGlobalConfig config) {
    if (!account.isActive) {
      return account.warningMessage.isNotEmpty
          ? account.warningMessage
          : 'تم إيقاف هذا الحساب من الإدارة. تواصل مع الإدارة لإعادة تفعيله.';
    }
    if (!config.isAppActive) {
      return config.maintenanceMessage.isNotEmpty
          ? config.maintenanceMessage
          : 'التطبيق متوقف مؤقتاً من الإدارة.';
    }
    if (account.isTrial && account.hasCustomWarning) return account.warningMessage;
    if (account.isTrial) return config.defaultTrialWarning;
    return config.globalOfficialWarning;
  }

  Future<List<CloudNotification>> _collectNotifications(
    String uid,
    String idToken,
  ) async {
    final userNotifications = await _service.fetchUserNotifications(
      uid,
      idToken: idToken,
    );
    var globalNotifications = const <CloudNotification>[];
    try {
      globalNotifications = await _service.fetchGlobalNotifications(idToken);
    } on CloudHttpException {
      globalNotifications = const <CloudNotification>[];
    }

    final seenAtRaw = await _read(SettingKeys.cloudGlobalSeenAt);
    final seenAt = seenAtRaw == null ? null : DateTime.tryParse(seenAtRaw);

    final merged = <CloudNotification>[
      ...userNotifications,
      ...globalNotifications.map(
        (notification) => notification.copyWith(
          isRead: seenAt != null && !notification.createdAt.isAfter(seenAt),
        ),
      ),
    ];
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  Future<void> _persistSession(CloudSession session) async {
    await _write(SettingKeys.cloudAccountUid, session.uid);
    await _write(SettingKeys.cloudRefreshToken, session.refreshToken);
  }

  Future<CloudAccount?> _cachedAccount() async {
    final uid = await _read(SettingKeys.cloudAccountUid);
    final phone = await _read(SettingKeys.cloudPhone);
    if (uid == null || phone == null) return null;
    final networkName = await _read(SettingKeys.cloudNetworkName) ?? '';
    final isTrial = (await _read(SettingKeys.cloudIsTrial)) != 'false';
    final isActive = (await _read(SettingKeys.cloudIsActive)) != 'false';
    final subscriptionEndRaw = await _read(SettingKeys.cloudSubscriptionEnd);
    return CloudAccount(
      uid: uid,
      phone: phone,
      networkName: networkName,
      isTrial: isTrial,
      isActive: isActive,
      subscriptionEnd:
          subscriptionEndRaw == null ? null : DateTime.tryParse(subscriptionEndRaw),
    );
  }

  void _startTimer() {
    _syncTimer ??= Timer.periodic(
      CloudConfig.syncInterval,
      (_) => unawaited(sync()),
    );
  }

  void _stopTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<String?> _read(String key) async {
    final result = await _settings.find(key);
    if (result is Success<AppSetting?>) return result.value?.value;
    return null;
  }

  Future<void> _write(String key, String value) async {
    await _settings.save(
      AppSetting(key: key, value: value, updatedAt: _clock.now()),
    );
  }

  Future<void> _clear(String key) async {
    await _write(key, '');
  }

  String get statusSummary {
    final current = state.value;
    final account = current.account;
    if (account == null) {
      switch (current.phase) {
        case AccountPhase.unconfigured:
          return 'خدمة الحساب غير مربوطة';
        case AccountPhase.loading:
          return 'جارٍ التحقق من الحساب…';
        case AccountPhase.signedOut:
          return 'لا يوجد حساب مسجّل على هذا الجهاز';
        case AccountPhase.blocked:
          return current.message.isEmpty ? 'الحساب موقوف' : current.message;
        case AccountPhase.ready:
          return '—';
      }
    }
    final buffer = StringBuffer(account.statusLabel);
    if (account.networkName.isNotEmpty) buffer.write(' · ${account.networkName}');
    if (account.phone.isNotEmpty) buffer.write(' · ${account.phone}');
    final remaining = account.remainingDays;
    if (remaining != null) {
      buffer.write(remaining >= 0 ? ' · متبقٍ $remaining يوم' : ' · انتهى الاشتراك');
    }
    if (current.offline) buffer.write(' · آخر حالة محفوظة (بلا إنترنت)');
    return buffer.toString();
  }

  void dispose() {
    _stopTimer();
    state.dispose();
  }
}
