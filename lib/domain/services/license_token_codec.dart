import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../core/result.dart';

/// رمز ترخيص قابل للتحقق دون اتصال.
///
/// الصيغة: KRT1.<base64url(payload JSON)>.<base64url(Ed25519 signature)>
/// المفتاح الخاص لا يدخل التطبيق أبداً؛ التطبيق يحمل المفتاح العام فقط.
final class LicenseTokenCodec {
  LicenseTokenCodec._();

  static const product = 'krotak-pro';
  static const _prefix = 'KRT1';
  // المفتاح العام المقابل للمفتاح الإداري المحفوظ خارج المستودع.
  static const publicKeyBase64Url = '6-2qyvxff2Nb_AzGNtwN57cUpwbJ2z7N7YAiRti1BJc';

  static Future<Result<LicenseTokenData>> verify(String raw) async {
    final token = raw.trim();
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != _prefix) {
      return const Failure(AppFailure(
        code: 'license_token_format',
        message: 'رمز الترخيص غير صالح أو ناقص.',
      ));
    }
    try {
      final payloadBytes = _decode(parts[1]);
      final signatureBytes = _decode(parts[2]);
      final payload = jsonDecode(utf8.decode(payloadBytes));
      if (payload is! Map) {
        return const Failure(AppFailure(
          code: 'license_token_payload',
          message: 'بيانات رمز الترخيص غير صالحة.',
        ));
      }
      final publicKey = SimplePublicKey(
        _decode(publicKeyBase64Url),
        type: KeyPairType.ed25519,
      );
      final valid = await Ed25519().verify(
        payloadBytes,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
      if (!valid) {
        return const Failure(AppFailure(
          code: 'license_token_signature',
          message: 'توقيع رمز الترخيص غير صحيح.',
        ));
      }
      final map = Map<String, dynamic>.from(payload as Map);
      final id = map['id']?.toString().trim() ?? '';
      final productName = map['product']?.toString() ?? '';
      final issuedAt = DateTime.tryParse(map['iat']?.toString() ?? '');
      final expiresAtRaw = map['exp']?.toString();
      final expiresAt = expiresAtRaw == null || expiresAtRaw == 'null'
          ? null
          : DateTime.tryParse(expiresAtRaw);
      if (id.isEmpty || productName != product || issuedAt == null) {
        return const Failure(AppFailure(
          code: 'license_token_claims',
          message: 'بيانات رمز الترخيص غير مكتملة.',
        ));
      }
      return Success(LicenseTokenData(
        token: token,
        id: id,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        deviceBinding: map['device']?.toString(),
      ));
    } on FormatException {
      return const Failure(AppFailure(
        code: 'license_token_encoding',
        message: 'ترميز رمز الترخيص غير صالح.',
      ));
    } catch (_) {
      return const Failure(AppFailure(
        code: 'license_token_invalid',
        message: 'تعذر التحقق من رمز الترخيص.',
      ));
    }
  }

  static List<int> _decode(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    return base64.decode(normalized.padRight(
      normalized.length + ((4 - normalized.length % 4) % 4),
      '=',
    ));
  }
}

final class LicenseTokenData {
  const LicenseTokenData({
    required this.token,
    required this.id,
    required this.issuedAt,
    required this.expiresAt,
    this.deviceBinding,
  });
  final String token;
  final String id;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final String? deviceBinding;
}
