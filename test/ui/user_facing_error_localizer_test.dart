import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/rejection_code_labels.dart';
import 'package:net_app/ui/errors/user_facing_error_localizer.dart';

/// WP-S3 — حارس مصدري: كل رمز خطأ مكتوب في `lib/**` يجب أن يُترجم إلى نص
/// عربي، وأي رمز غير معروف يسقط إلى الرسالة العامة العربية — بلا استثناء.
void main() {
  // أسماء تقنية معتمدة تبقى لاتينية (أسماء ملفات/علامة/مثال رقم جوال).
  const allowedLatin = [
    'Krotak Pro',
    'PDF',
    'Excel',
    'CSV',
    'xlsx',
    '77xxxxxxx',
    'PNG',
  ];

  final latin = RegExp('[A-Za-z]');
  final codePattern = RegExp("code:\\s*'([a-z0-9_]+)'");

  String stripAllowed(String text) {
    var out = text;
    for (final term in allowedLatin) {
      out = out.replaceAll(term, '');
    }
    return out;
  }

  test('كل رمز خطأ في lib/ يُترجم إلى نص عربي بلا أحرف لاتينية', () {
    final codes = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      for (final match in codePattern.allMatches(content)) {
        codes.add(match.group(1)!);
      }
    }

    expect(codes, isNotEmpty, reason: 'لم يُعثر على أي رمز خطأ — راجع نمط المسح');

    final missing = <String>[];
    for (final code in codes) {
      final message = UserFacingErrorLocalizer.localize(code);
      final text = stripAllowed('${message.text} ${message.action ?? ''}');
      if (latin.hasMatch(text)) {
        missing.add('$code => ${message.text}');
      }
      expect(message.text.trim(), isNotEmpty, reason: 'رمز بلا نص: $code');
      expect(message.text.contains(code), isFalse,
          reason: 'الرمز البرمجي ظهر للمستخدم: $code');
    }
    expect(missing, isEmpty, reason: 'رموز بلا ترجمة عربية نقية');
  });

  test('أكواد الرفض المعروفة كلها لها نص عربي وإجراء', () {
    for (final code in RejectionCodeLabels.ar.keys) {
      final message = UserFacingErrorLocalizer.localize(code);
      expect(message.text.trim(), isNotEmpty, reason: code);
      expect(latin.hasMatch(stripAllowed(message.text)), isFalse, reason: code);
      expect(message.action, isNotNull, reason: 'لا إجراء مقترح للرمز $code');
    }
  });

  test('رمز غير معروف يسقط إلى الرسالة العامة ولا يُعرض الرمز', () {
    final message = UserFacingErrorLocalizer.localize('totally_unknown_code_xyz');
    expect(message.text, UserFacingErrorLocalizer.genericText);
    expect(message.text.contains('totally_unknown_code_xyz'), isFalse);
  });

  test('يقرأ AppFailure وFailure وResult', () {
    const failure = AppFailure(code: 'card_not_found', message: 'Card not found');
    expect(localizedError(failure), 'الكرت غير موجود.');
    expect(localizedError(const Failure<String>(failure)), 'الكرت غير موجود.');
    expect(localizedError(const Success<String>('x')), UserFacingErrorLocalizer.genericText);
    expect(localizedError(null), UserFacingErrorLocalizer.genericText);
    expect(localizedError(''), UserFacingErrorLocalizer.genericText);
  });

  test('لا يُسرّب نص إنجليزي جاهز من الطبقات الدنيا', () {
    const raw = AppFailure(code: 'database_not_available', message: 'Database not available');
    expect(localizedError(raw), 'قاعدة البيانات غير متاحة.');
    expect(localizedError(raw).contains('Database'), isFalse);
  });
}
