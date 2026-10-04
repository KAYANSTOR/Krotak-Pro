import 'cloud_http.dart';

/// جلسة مصادقة Firebase (تُخزَّن محلياً: المعرّف + رمز التجديد).
final class CloudSession {
  const CloudSession({
    required this.uid,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String uid;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// يُعتبر الرمز منتهياً قبل دقيقتين حتى لا يبدأ طلب وينتهي أثناء التنفيذ.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));
}

/// عميل Firebase REST: المصادقة (Identity Toolkit) + Firestore.
///
/// يستخدم واجهات Firebase الرسمية عبر HTTPS، فالنتيجة **بيانات حقيقية** في نفس
/// المشروع الذي تقرأ منه لوحة الإدارة: مستخدمون في Authentication، ووثائق في
/// Firestore تخضع لقواعد الأمان المنشورة.
final class FirebaseRestClient {
  FirebaseRestClient({
    required this.apiKey,
    required this.projectId,
    CloudHttp? http,
  }) : _http = http ?? CloudHttp();

  final String apiKey;
  final String projectId;
  final CloudHttp _http;

  static const _identityBase = 'https://identitytoolkit.googleapis.com/v1';
  static const _tokenBase = 'https://securetoken.googleapis.com/v1';

  String get _documentsBase =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  // ── المصادقة ────────────────────────────────────────────────────────

  Future<CloudSession> signUp({
    required String email,
    required String password,
  }) async {
    final res = await _http.postJson(
      '$_identityBase/accounts:signUp?key=$apiKey',
      <String, dynamic>{
        'email': email,
        'password': password,
        'returnSecureToken': true,
      },
    );
    return _sessionFromAuth(res);
  }

  Future<CloudSession> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _http.postJson(
      '$_identityBase/accounts:signInWithPassword?key=$apiKey',
      <String, dynamic>{
        'email': email,
        'password': password,
        'returnSecureToken': true,
      },
    );
    return _sessionFromAuth(res);
  }

  /// تجديد الجلسة باستخدام رمز التجديد المحفوظ.
  Future<CloudSession> refresh(CloudSession previous) async {
    final res = await _http.postForm(
      '$_tokenBase/token?key=$apiKey',
      <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': previous.refreshToken,
      },
    );
    final idToken = res['id_token']?.toString();
    final refreshToken = res['refresh_token']?.toString();
    final expiresIn = int.tryParse(res['expires_in']?.toString() ?? '') ?? 3600;
    final uid = res['user_id']?.toString() ?? previous.uid;
    if (idToken == null || idToken.isEmpty || refreshToken == null) {
      throw const CloudHttpException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.',
      );
    }
    return CloudSession(
      uid: uid,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  CloudSession _sessionFromAuth(Map<String, dynamic> res) {
    final idToken = res['idToken']?.toString() ?? '';
    final refreshToken = res['refreshToken']?.toString() ?? '';
    final uid = res['localId']?.toString() ?? '';
    final expiresIn = int.tryParse(res['expiresIn']?.toString() ?? '') ?? 3600;
    if (idToken.isEmpty || refreshToken.isEmpty || uid.isEmpty) {
      throw const CloudHttpException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'لم يكتمل تسجيل الدخول. أعد المحاولة.',
      );
    }
    return CloudSession(
      uid: uid,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  // ── Firestore ───────────────────────────────────────────────────────

  /// يقرأ وثيقة ويعيد حقولها، أو `null` إذا لم تكن موجودة.
  Future<Map<String, dynamic>?> getDocument(
    String path, {
    required String idToken,
  }) async {
    try {
      final res = await _http.getJson(
        '$_documentsBase/$path',
        bearer: idToken,
      );
      return decodeDocument(res);
    } on CloudHttpException catch (error) {
      if (error.statusCode == 404 || error.code == 'NOT_FOUND') return null;
      rethrow;
    }
  }

  /// يقرأ مجموعة فرعية (بحد أقصى [pageSize] وثيقة).
  Future<List<Map<String, dynamic>>> listDocuments(
    String path, {
    required String idToken,
    int pageSize = 50,
  }) async {
    try {
      final res = await _http.getJson(
        '$_documentsBase/$path?pageSize=$pageSize',
        bearer: idToken,
      );
      final documents = res['documents'];
      if (documents is! List) return const <Map<String, dynamic>>[];
      return documents
          .whereType<Map>()
          .map((doc) {
            final fields = decodeDocument(doc.cast<String, dynamic>());
            final name = doc['name']?.toString() ?? '';
            fields['__id'] = name.split('/').last;
            return fields;
          })
          .toList(growable: false);
    } on CloudHttpException catch (error) {
      if (error.statusCode == 404 || error.code == 'NOT_FOUND') {
        return const <Map<String, dynamic>>[];
      }
      rethrow;
    }
  }

  /// يكتب حقولاً محددة فقط (updateMask) حتى لا تُمسح حقول الإدارة مثل
  /// `commission_rate` أو `warning_message` عند تحديث بيانات الحساب.
  Future<void> patchDocument(
    String path,
    Map<String, dynamic> fields, {
    required String idToken,
    required List<String> fieldPaths,
  }) async {
    final mask = fieldPaths
        .map((f) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(f)}')
        .join('&');
    final url = mask.isEmpty
        ? '$_documentsBase/$path'
        : '$_documentsBase/$path?$mask';
    await _http.patchJson(
      url,
      <String, dynamic>{'fields': encodeFields(fields)},
      bearer: idToken,
    );
  }
}

// ── ترميز/فك ترميز قيم Firestore ──────────────────────────────────────

Map<String, dynamic> encodeFields(Map<String, dynamic> fields) {
  return fields.map((key, value) => MapEntry(key, encodeValue(value)));
}

Map<String, dynamic> encodeValue(Object? value) {
  if (value == null) return <String, dynamic>{'nullValue': null};
  if (value is bool) return <String, dynamic>{'booleanValue': value};
  if (value is int) return <String, dynamic>{'integerValue': value.toString()};
  if (value is double) return <String, dynamic>{'doubleValue': value};
  if (value is DateTime) {
    return <String, dynamic>{
      'timestampValue': value.toUtc().toIso8601String(),
    };
  }
  if (value is List) {
    return <String, dynamic>{
      'arrayValue': <String, dynamic>{
        'values': value.map(encodeValue).toList(growable: false),
      },
    };
  }
  if (value is Map) {
    return <String, dynamic>{
      'mapValue': <String, dynamic>{
        'fields': encodeFields(value.cast<String, dynamic>()),
      },
    };
  }
  return <String, dynamic>{'stringValue': value.toString()};
}

Object? decodeValue(Object? raw) {
  if (raw is! Map) return null;
  final value = raw.cast<String, dynamic>();
  if (value.containsKey('stringValue')) return value['stringValue']?.toString();
  if (value.containsKey('integerValue')) {
    return int.tryParse(value['integerValue']?.toString() ?? '');
  }
  if (value.containsKey('doubleValue')) {
    final num? number = value['doubleValue'] is num
        ? value['doubleValue'] as num
        : num.tryParse(value['doubleValue']?.toString() ?? '');
    return number?.toDouble();
  }
  if (value.containsKey('booleanValue')) return value['booleanValue'] == true;
  if (value.containsKey('timestampValue')) {
    return DateTime.tryParse(value['timestampValue']?.toString() ?? '')?.toLocal();
  }
  if (value.containsKey('nullValue')) return null;
  if (value.containsKey('arrayValue')) {
    final array = value['arrayValue'];
    if (array is! Map) return const <Object?>[];
    final values = array['values'];
    if (values is! List) return const <Object?>[];
    return values.map(decodeValue).toList(growable: false);
  }
  if (value.containsKey('mapValue')) {
    final map = value['mapValue'];
    if (map is! Map) return const <String, dynamic>{};
    return decodeDocument(map.cast<String, dynamic>());
  }
  return null;
}

/// يفك ترميز وثيقة Firestore كاملة إلى خريطة Dart عادية.
Map<String, dynamic> decodeDocument(Map<String, dynamic> document) {
  final fields = document['fields'];
  if (fields is! Map) return <String, dynamic>{};
  return fields.map(
    (key, value) => MapEntry(key.toString(), decodeValue(value)),
  );
}
