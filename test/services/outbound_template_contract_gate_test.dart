import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/outbound_template_renderer.dart';

/// بوابة عقد القوالب — الخطة §10.3 ومعايير AC-T1..AC-T3.
///
/// الحالات التي يمنعها هذا الملف قبل أي تعديل على القوالب:
/// - قالب يستخدم متغيرًا غير معلن في عقده.
/// - متغير مطلوب غير معلن، أو معلن بلا قيمة معاينة.
/// - نص مزروع لا يُحل بالكامل فيبقى `{...}` أو `%name` في رسالة عميل.
/// - مفتاح مكرر أو غير مسجّل في العقد المركزي.
void main() {
  test('every seeded body only uses variables declared in its own contract', () {
    for (final definition in OutboundTemplateCatalog.definitions) {
      final used = <String>{
        ...OutboundTemplateRenderer.bracePlaceholders(definition.initialBody),
        ...OutboundTemplateRenderer.percentPlaceholders(definition.initialBody),
      };
      final unknown = used.difference(definition.variables);
      expect(unknown, isEmpty,
          reason: '${definition.key} يستخدم متغيرات غير معلنة: $unknown');
    }
  });

  test('required variables are declared and every declared variable has a sample',
      () {
    final samples = OutboundTemplateCatalog.previewSamples.keys.toSet();
    for (final definition in OutboundTemplateCatalog.definitions) {
      final undeclared =
          definition.requiredVariables.difference(definition.variables);
      expect(undeclared, isEmpty,
          reason: '${definition.key}: متغيرات مطلوبة غير معلنة: $undeclared');
      final withoutSample = definition.variables.difference(samples);
      expect(withoutSample, isEmpty,
          reason: '${definition.key}: متغيرات بلا قيمة معاينة: $withoutSample');
    }
  });

  test('the seeded body of every template renders with no placeholder left', () {
    for (final definition in OutboundTemplateCatalog.definitions) {
      final rendered = OutboundTemplateRenderer.renderStrict(
        template: definition.initialBody,
        values: OutboundTemplateCatalog.previewValuesFor(definition),
      );
      expect(rendered, isA<Success<String>>(),
          reason: '${definition.key}: النص المزروع لم يُحل كاملًا');
      final body = (rendered as Success<String>).value;
      expect(OutboundTemplateRenderer.unresolvedPlaceholders(body), isEmpty,
          reason: '${definition.key}: بقي متغير غير محلول في النص');
    }
  });

  test('template keys are unique and resolvable by key', () {
    final keys = <String>[];
    for (final definition in OutboundTemplateCatalog.definitions) {
      expect(keys, isNot(contains(definition.key)),
          reason: 'مفتاح قالب مكرر: ${definition.key}');
      keys.add(definition.key);
      expect(OutboundTemplateCatalog.isRegistered(definition.key), isTrue,
          reason: '${definition.key} غير قابل للبحث في العقد');
      expect(OutboundTemplateCatalog.byKey(definition.key)?.title.isNotEmpty,
          isTrue,
          reason: '${definition.key} بلا عنوان للمشغّل');
    }
    expect(
      OutboundTemplateCatalog.initialBodies().keys.toSet(),
      keys.toSet(),
      reason: 'نصوص الزرع يجب أن تغطي كل قالب مسجّل',
    );
  });
}
