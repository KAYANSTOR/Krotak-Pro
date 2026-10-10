import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/errors/user_facing_error_localizer.dart';

/// WP-7 — حارسان:
/// 1. مصدري: لا تعرض أي شاشة `error.message` أو رمزًا برمجيًا مباشرة.
/// 2. سلوكي: كل خطأ يتحوّل إلى نص عربي، وأسباب الرفض الرمزية تُترجم مع إجراء.
void main() {
  test('لا استعمال مباشر لـ error.message في lib/ui', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/ui').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('errors/user_facing_error_localizer.dart')) continue;
      final content = entity.readAsStringSync();
      for (final line in content.split('\n')) {
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('.error.message')) {
          offenders.add('${entity.path}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'استعمل localizedError بدل error.message:\n${offenders.join('\n')}');
  });

  test('أسباب الرفض الرمزية تُترجم إلى عربية مع إجراء', () {
    expect(UserFacingErrorLocalizer.looksLikeCode('voucher_unavailable'), isTrue);
    expect(UserFacingErrorLocalizer.looksLikeCode('noActiveTemplate'), isTrue);
    expect(UserFacingErrorLocalizer.looksLikeCode('سبب عربي'), isFalse);
    expect(UserFacingErrorLocalizer.looksLikeCode(''), isFalse);
    expect(UserFacingErrorLocalizer.looksLikeCode(null), isFalse);

    final codeReason = UserFacingErrorLocalizer.reasonText('voucher_unavailable');
    expect(codeReason.contains('voucher_unavailable'), isFalse);
    expect(RegExp('[A-Za-z]').hasMatch(codeReason), isFalse, reason: codeReason);
    expect(codeReason.contains('—'), isTrue, reason: 'لا يوجد إجراء مقترح');

    expect(
      UserFacingErrorLocalizer.reasonText('تعذر تحديد هوية العميل'),
      'تعذر تحديد هوية العميل',
    );
    expect(UserFacingErrorLocalizer.reasonText('   '), 'سبب غير محدد');
    expect(UserFacingErrorLocalizer.reasonText(null), 'سبب غير محدد');

    final unknown = UserFacingErrorLocalizer.reasonText('zzz_unknown_code');
    expect(unknown, UserFacingErrorLocalizer.genericText);
  });
}
