import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/cloud_config.dart';

/// خطأ موحّد لطبقة الاتصال السحابي، برسالة عربية جاهزة للعرض.
final class CloudHttpException implements Exception {
  const CloudHttpException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isNetworkFailure => statusCode == 0;

  @override
  String toString() => 'CloudHttpException($statusCode, $code): $message';
}

/// عميل HTTP صغير (JSON + form) مبني على `dart:io` — لا يضيف أي حزمة خارجية
/// إلى المشروع، ويعمل على Android/iOS دون إعدادات Gradle إضافية.
final class CloudHttp {
  CloudHttp({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = CloudConfig.requestTimeout;
    _client.userAgent = 'KrotakPro/1.0';
  }

  final HttpClient _client;

  Future<Map<String, dynamic>> getJson(String url, {String? bearer}) =>
      _send('GET', url, bearer: bearer);

  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, dynamic> body, {
    String? bearer,
  }) =>
      _send('POST', url, body: body, bearer: bearer);

  Future<Map<String, dynamic>> patchJson(
    String url,
    Map<String, dynamic> body, {
    String? bearer,
  }) =>
      _send('PATCH', url, body: body, bearer: bearer);

  Future<Map<String, dynamic>> postForm(
    String url,
    Map<String, String> form,
  ) =>
      _send('POST', url, form: form);

  void close() => _client.close(force: true);

  Future<Map<String, dynamic>> _send(
    String method,
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? form,
    String? bearer,
  }) async {
    try {
      final request = await _client.openUrl(method, Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer != null && bearer.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          form.entries
              .map((e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
              .join('&'),
        );
      } else if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(CloudConfig.requestTimeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(CloudConfig.requestTimeout);

      final decoded = _decode(text);
      if (response.statusCode >= 400) {
        final code = _errorCode(decoded, response.statusCode);
        throw CloudHttpException(
          statusCode: response.statusCode,
          code: code,
          message: arabicCloudMessage(code, statusCode: response.statusCode),
        );
      }
      return decoded;
    } on CloudHttpException {
      rethrow;
    } on TimeoutException {
      throw const CloudHttpException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'انتهت مهلة الاتصال بالخادم. تحقق من الإنترنت وأعد المحاولة.',
      );
    } on SocketException {
      throw const CloudHttpException(
        statusCode: 0,
        code: 'network_unreachable',
        message: 'تعذر الاتصال بالإنترنت. تحقق من الشبكة وأعد المحاولة.',
      );
    } on HttpException {
      throw const CloudHttpException(
        statusCode: 0,
        code: 'network_failed',
        message: 'فشل الاتصال بالخادم. أعد المحاولة بعد قليل.',
      );
    } on FormatException {
      throw const CloudHttpException(
        statusCode: 0,
        code: 'bad_response',
        message: 'رد غير مفهوم من الخادم. أعد المحاولة بعد قليل.',
      );
    }
  }

  Map<String, dynamic> _decode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return <String, dynamic>{'data': decoded};
  }

  /// يستخرج رمز الخطأ من ردود Identity Toolkit أو Firestore.
  String _errorCode(Map<String, dynamic> decoded, int statusCode) {
    final error = decoded['error'];
    if (error is Map) {
      final message = error['message']?.toString();
      if (message != null && message.isNotEmpty) {
        // رسائل Firestore تأتي بصيغة «PERMISSION_DENIED: ...».
        final first = message.split(':').first.trim();
        if (first.isNotEmpty) return first;
      }
      final status = error['status']?.toString();
      if (status != null && status.isNotEmpty) return status;
    }
    return 'http_$statusCode';
  }
}

/// ترجمة رموز أخطاء Firebase إلى رسائل عربية واضحة للمشغّل.
String arabicCloudMessage(String code, {int statusCode = 0}) {
  switch (code) {
    case 'EMAIL_EXISTS':
      return 'هذا الرقم مسجّل مسبقاً. سجّل الدخول بكلمة المرور نفسها.';
    case 'EMAIL_NOT_FOUND':
    case 'INVALID_PASSWORD':
    case 'INVALID_LOGIN_CREDENTIALS':
    case 'INVALID_EMAIL':
      return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
    case 'WEAK_PASSWORD':
    case 'MISSING_PASSWORD':
      return 'كلمة المرور ضعيفة — استخدم 6 أحرف على الأقل.';
    case 'TOO_MANY_ATTEMPTS_TRY_LATER':
      return 'محاولات كثيرة متكررة. انتظر قليلاً ثم أعد المحاولة.';
    case 'OPERATION_NOT_ALLOWED':
      return 'تسجيل الدخول بالبريد/كلمة المرور غير مُفعّل في مشروع Firebase.';
    case 'USER_DISABLED':
      return 'هذا الحساب معطّل من الإدارة.';
    case 'PERMISSION_DENIED':
      return 'لا تملك صلاحية الوصول إلى هذه البيانات.';
    case 'NOT_FOUND':
      return 'لا توجد بيانات محفوظة لهذا الحساب.';
    case 'UNAUTHENTICATED':
      return 'انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.';
    case 'QUOTA_EXCEEDED':
      return 'تم تجاوز حصة الخدمة مؤقتاً. أعد المحاولة بعد قليل.';
    case 'cloud_not_configured':
      return 'لم يتم ربط خدمة الحساب بعد. راجع إعداد CloudConfig.';
    case 'network_timeout':
    case 'network_unreachable':
    case 'network_failed':
      return 'تعذر الوصول إلى الخادم. تحقق من الإنترنت وأعد المحاولة.';
    default:
      if (statusCode == 400) return 'طلب غير صالح ($code).';
      if (statusCode == 401 || statusCode == 403) {
        return 'لا تملك صلاحية الوصول إلى هذه البيانات.';
      }
      if (statusCode == 429) return 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.';
      if (statusCode >= 500) return 'الخادم غير متاح مؤقتاً. أعد المحاولة بعد قليل.';
      return 'تعذر إكمال العملية ($code).';
  }
}