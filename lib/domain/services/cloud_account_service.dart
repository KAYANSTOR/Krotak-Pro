import '../../core/app_brand.dart';
import '../../core/cloud_config.dart';
import '../../data/cloud/cloud_http.dart';
import '../../data/cloud/firebase_rest_client.dart';
import '../entities/cloud_account.dart';

/// خدمة حساب الشبكة: تسجيل، دخول، قراءة الحالة، الإشعارات، الإعداد العام.
///
/// تكتب وتقرأ نفس وثائق Firestore التي تستخدمها لوحة الإدارة:
/// - `users/{uid}` — حالة الحساب والاشتراك.
/// - `networks/{uid}/_metadata/info` — اسم الشبكة والهاتف.
/// - `users/{uid}/notifications` — إشعارات الإدارة لهذا الحساب.
/// - `app_settings/global_config` — الإعداد العام وحالة التطبيق.
final class CloudAccountService {
  CloudAccountService({FirebaseRestClient? client})
      : _client = client ??
            FirebaseRestClient(
              apiKey: CloudConfig.apiKey,
              projectId: CloudConfig.projectId,
            );

  final FirebaseRestClient _client;

  bool get isConfigured => CloudConfig.isConfigured;

  void ensureConfigured() {
    if (!isConfigured) {
      throw const CloudHttpException(
        statusCode: 0,
        code: 'cloud_not_configured',
        message: 'لم يتم ربط خدمة الحساب بعد. راجع إعداد CloudConfig.',
      );
    }
  }

  // ── تحويل رقم الهاتف ────────────────────────────────────────────────

  /// يحوّل الرقم إلى صيغة دولية بالأرقام فقط (اليمن افتراضياً: 967).
  static String normalizePhone(String raw) {
    final digits = _toAsciiDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('00')) return digits.substring(2);
    if (digits.startsWith('967')) return digits;
    if (digits.startsWith('0')) return '967${digits.substring(1)}';
    if (digits.length <= 9) return '967$digits';
    return digits;
  }

  /// يدعم أرقام لوحة المفاتيح العربية قبل تطبيق التطبيع الدولي.
  static String _toAsciiDigits(String raw) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const eastern = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final codePoint in raw.runes) {
      final char = String.fromCharCode(codePoint);
      final arabicIndex = arabic.indexOf(char);
      if (arabicIndex >= 0) {
        out.write(arabicIndex);
        continue;
      }
      final easternIndex = eastern.indexOf(char);
      if (easternIndex >= 0) {
        out.write(easternIndex);
        continue;
      }
      out.write(char);
    }
    return out.toString();
  }

  static bool isValidPhone(String raw) {
    final normalized = normalizePhone(raw);
    return normalized.length >= 11 && normalized.length <= 15;
  }

  /// الرقم يُحوَّل داخلياً إلى بريد تقني ثابت لأن Firebase لا يدعم الرقم وكلمة
  /// المرور مباشرة. المستخدم لا يرى هذا البريد ولا يحتاجه.
  static String emailForPhone(String normalizedPhone) =>
      '$normalizedPhone@${CloudConfig.emailDomain}';

  // ── التسجيل والدخول ─────────────────────────────────────────────────

  /// إنشاء حساب جديد يبدأ **تجريبياً** مباشرة، ويظهر في لوحة الإدارة.
  Future<CloudSession> register({
    required String networkName,
    required String phone,
    required String password,
  }) async {
    ensureConfigured();
    final normalized = normalizePhone(phone);
    final session = await _client.signUp(
      email: emailForPhone(normalized),
      password: password,
    );

    final config = await fetchGlobalConfig(session.idToken);
    final now = DateTime.now();
    final trialEnd = now.add(Duration(days: config.defaultTrialDays));

    await _client.patchDocument(
      'users/${session.uid}',
      <String, dynamic>{
        'uid': session.uid,
        'phone': normalized,
        'network_name': networkName,
        'is_active': true,
        'is_trial': true,
        'subscription_end_date': trialEnd,
        'trial_days': config.defaultTrialDays,
        'platform': 'android',
        'app_version': AppBrand.version,
        'created_at': now,
        'last_seen_at': now,
      },
      idToken: session.idToken,
      fieldPaths: const <String>[
        'uid',
        'phone',
        'network_name',
        'is_active',
        'is_trial',
        'subscription_end_date',
        'trial_days',
        'platform',
        'app_version',
        'created_at',
        'last_seen_at',
      ],
    );

    await saveNetworkMetadata(
      uid: session.uid,
      networkName: networkName,
      phone: normalized,
      idToken: session.idToken,
    );

    return session;
  }

  Future<CloudSession> signIn({
    required String phone,
    required String password,
  }) async {
    ensureConfigured();
    CloudHttpException? lastInvalidCredentials;
    for (final candidate in _phoneCandidates(phone)) {
      try {
        return await _client.signIn(
          email: emailForPhone(candidate),
          password: password,
        );
      } on CloudHttpException catch (error) {
        if (!_isInvalidCredentials(error.code)) rethrow;
        lastInvalidCredentials = error;
      }
    }
    throw lastInvalidCredentials ??
        const CloudHttpException(
          statusCode: 400,
          code: 'INVALID_LOGIN_CREDENTIALS',
          message: 'رقم الهاتف أو كلمة المرور غير صحيحة.',
        );
  }

  /// يدعم الحسابات التي سُجلت قبل توحيد تخزين الرقم بصيغة 967 الدولية.
  static Iterable<String> _phoneCandidates(String raw) sync* {
    final digits = _toAsciiDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = normalizePhone(raw);
    final candidates = <String>{normalized};
    if (digits.startsWith('967') && digits.length > 3) {
      candidates.add(digits.substring(3));
    } else if (digits.startsWith('0') && digits.length > 1) {
      candidates.add(digits.substring(1));
    } else if (digits.isNotEmpty) {
      candidates.add('0$digits');
    }
    yield* candidates.where((value) => value.isNotEmpty);
  }

  static bool _isInvalidCredentials(String code) =>
      code == 'INVALID_LOGIN_CREDENTIALS' ||
      code == 'INVALID_PASSWORD' ||
      code == 'EMAIL_NOT_FOUND' ||
      code == 'INVALID_EMAIL';

  /// استعادة جلسة محفوظة محلياً (بعد إعادة تشغيل التطبيق).
  Future<CloudSession> restoreSession({
    required String uid,
    required String refreshToken,
  }) async {
    ensureConfigured();
    final stale = CloudSession(
      uid: uid,
      idToken: '',
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    return _client.refresh(stale);
  }

  Future<CloudSession> refreshSession(CloudSession session) async {
    ensureConfigured();
    if (!session.isExpired) return session;
    return _client.refresh(session);
  }

  // ── قراءة الحالة ────────────────────────────────────────────────────

  Future<CloudAccount?> fetchAccount(
    String uid, {
    required String idToken,
  }) async {
    final data = await _client.getDocument('users/$uid', idToken: idToken);
    if (data == null) return null;
    var accountData = data;
    // توافق مع الحسابات التي خزّنت الهاتف والاسم في metadata فقط.
    if ((accountData['phone']?.toString().trim().isEmpty ?? true)) {
      final metadata = await _client.getDocument(
        'networks/$uid/_metadata/info',
        idToken: idToken,
      );
      if (metadata != null) {
        accountData = <String, dynamic>{
          ...accountData,
          if ((accountData['phone']?.toString().trim().isEmpty ?? true) &&
              metadata['phoneNumber'] != null)
            'phone': metadata['phoneNumber'],
          if ((accountData['network_name']?.toString().trim().isEmpty ?? true) &&
              metadata['name'] != null)
            'network_name': metadata['name'],
        };
      }
    }
    return CloudAccount.fromMap(uid, accountData);
  }

  /// يسجل جهاز Android الحالي للحساب حتى تستطيع لوحة الإدارة إرسال إشعارات موجهة.
  Future<void> upsertDeviceToken({
    required String uid,
    required String token,
    required String deviceId,
    required String idToken,
  }) async {
    if (uid.isEmpty || token.isEmpty || deviceId.isEmpty) return;
    await _client.patchDocument(
      'users/$uid/devices/$deviceId',
      <String, dynamic>{
        'token': token,
        'platform': 'android',
        'app_version': AppBrand.version,
        'updated_at': DateTime.now(),
        'enabled': true,
      },
      idToken: idToken,
      fieldPaths: const <String>[
        'token',
        'platform',
        'app_version',
        'updated_at',
        'enabled',
      ],
    );
  }

  Future<void> touchPresence({
    required String uid,
    required String idToken,
  }) async {
    await _client.patchDocument(
      'users/$uid',
      <String, dynamic>{
        'last_seen_at': DateTime.now(),
        'app_version': AppBrand.version,
      },
      idToken: idToken,
      fieldPaths: const <String>['last_seen_at', 'app_version'],
    );
  }

  /// يحدّث اسم الشبكة والهاتف (يظهران في لوحة الإدارة والتقارير).
  Future<void> saveNetworkMetadata({
    required String uid,
    required String networkName,
    required String phone,
    required String idToken,
  }) async {
    await _client.patchDocument(
      'networks/$uid/_metadata/info',
      <String, dynamic>{
        'networkId': uid,
        'name': networkName,
        'phoneNumber': phone,
        'description': '',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
      idToken: idToken,
      fieldPaths: const <String>[
        'networkId',
        'name',
        'phoneNumber',
        'description',
        'createdAt',
      ],
    );
  }

  Future<CloudGlobalConfig> fetchGlobalConfig(String idToken) async {
    try {
      final data = await _client.getDocument(
        'app_settings/global_config',
        idToken: idToken,
      );
      return CloudGlobalConfig.fromMap(data);
    } on CloudHttpException {
      // الإعداد العام غير متاح (أو غير منشور بعد) — نعمل بالقيم الافتراضية.
      return const CloudGlobalConfig();
    }
  }

  // ── الإشعارات ───────────────────────────────────────────────────────

  Future<List<CloudNotification>> fetchUserNotifications(
    String uid, {
    required String idToken,
  }) async {
    final documents = await _client.listDocuments(
      'users/$uid/notifications',
      idToken: idToken,
    );
    final notifications = <CloudNotification>[];
    for (final data in documents) {
      final parsed = CloudNotification.fromMap(data, isGlobal: false);
      if (parsed != null) notifications.add(parsed);
    }
    return notifications;
  }

  Future<List<CloudNotification>> fetchGlobalNotifications(
    String idToken,
  ) async {
    final documents = await _client.listDocuments(
      'app_settings/global_config/notifications',
      idToken: idToken,
    );
    final notifications = <CloudNotification>[];
    for (final data in documents) {
      final parsed = CloudNotification.fromMap(data, isGlobal: true);
      if (parsed != null) notifications.add(parsed);
    }
    return notifications;
  }

  Future<void> markNotificationRead({
    required String uid,
    required String notificationId,
    required String idToken,
  }) async {
    if (notificationId.isEmpty) return;
    await _client.patchDocument(
      'users/$uid/notifications/$notificationId',
      <String, dynamic>{'is_read': true},
      idToken: idToken,
      fieldPaths: const <String>['is_read'],
    );
  }
}
