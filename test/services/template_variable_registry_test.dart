import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/template_variable_registry.dart';

/// WP-S2 — سجل المتغيرات: مفتاح قانوني واحد، اسم عربي واحد، ومنع التكرار بعد
/// التطبيع. الحارس الأهم: **كل متغير معلن في عقد القوالب له تعريف في السجل**،
/// وإلا ظهر للمستخدم كود لاتيني أو متغير مجهول.
void main() {
  test('كل متغير معلن في عقد القوالب معروف في السجل', () {
    final unknown = <String>{};
    for (final definition in OutboundTemplateCatalog.definitions) {
      for (final variable in definition.variables) {
        if (!TemplateVariableRegistry.isKnown(variable)) unknown.add(variable);
      }
      for (final variable in definition.requiredVariables) {
        if (!TemplateVariableRegistry.isKnown(variable)) unknown.add(variable);
      }
    }
    expect(unknown, isEmpty, reason: 'متغيرات بلا تعريف في السجل: $unknown');
  });

  test('المرادفات تُطبَّع إلى المفتاح القانوني (D9 حسب الدلالة)', () {
    expect(TemplateVariableRegistry.canonical('CARDS'), 'cards');
    expect(TemplateVariableRegistry.canonical('CARDS') == 'CARDS', isFalse);
    expect(TemplateVariableRegistry.canonical('CARD_CODE'), 'serial');
    expect(TemplateVariableRegistry.canonical('CARD_SERIAL'), 'serial');
    expect(TemplateVariableRegistry.canonical('serial_number'), 'serial');
    expect(TemplateVariableRegistry.canonical('CODE'), 'secret');
    expect(TemplateVariableRegistry.canonical('SECRET'), 'secret');
    expect(TemplateVariableRegistry.canonical('secret'), 'secret');
    expect(TemplateVariableRegistry.canonical('QUANTITY_TEXT'), 'quantity');
    expect(TemplateVariableRegistry.canonical('CUSTOMER_PHONE'), 'customer_phone');
    expect(TemplateVariableRegistry.canonical('POS_NAME'), 'pos_name');
    expect(TemplateVariableRegistry.canonical('CARD_VALUE'), 'card_value');
    expect(TemplateVariableRegistry.canonical('NETWORK_NAME'), 'network_name');
  });

  test('رقم الكرت والرمز السري يبقيان منفصلين (قرار D9)', () {
    expect(TemplateVariableRegistry.canonical('serial'), isNot(TemplateVariableRegistry.canonical('secret')));
    expect(TemplateVariableRegistry.duplicatesIn(['serial', 'secret']), isEmpty);
    expect(TemplateVariableRegistry.duplicatesIn(['code', 'secret']), {'secret'});
    expect(TemplateVariableRegistry.duplicatesIn(['CARDS', 'cards']), {'cards'});
    expect(TemplateVariableRegistry.duplicatesIn(['cards', 'CARDS', 'cards']), {'cards'});
    expect(
      TemplateVariableRegistry.duplicatesIn(['amount', 'AMOUNT', 'reward_value']),
      {'amount'},
    );
    expect(
      TemplateVariableRegistry.duplicatesIn(['serial', 'CARD_CODE', 'CARD_SERIAL']),
      {'serial'},
    );
    expect(TemplateVariableRegistry.duplicatesIn(const []), isEmpty);
    expect(TemplateVariableRegistry.duplicatesIn(['  ', '']), isEmpty);
  });

  test('لا اسم عربي مكرر ولا اسم لاتيني في الأزرار', () {
    final labels = <String>[];
    final latin = RegExp('[A-Za-z]');
    for (final spec in TemplateVariableRegistry.specs) {
      expect(latin.hasMatch(spec.arabicName), isFalse, reason: spec.key);
      expect(spec.arabicName.trim(), isNotEmpty, reason: spec.key);
      labels.add(spec.arabicName);
    }
    expect(labels.toSet().length, labels.length, reason: 'أسماء عربية مكررة: $labels');
  });

  test('لا مفتاح قانوني مكرر ولا مرادف مشترك بين متغيرين', () {
    final seen = <String>{};
    for (final spec in TemplateVariableRegistry.specs) {
      for (final key in spec.allKeys) {
        expect(seen.add(key), isTrue, reason: 'مفتاح مكرر: $key');
      }
    }
  });

  test('أزرار الواجهة تُبنى من السجل بمفتاح قانوني فقط', () {
    final buttons = TemplateVariableRegistry.buttons();
    expect(buttons.length, TemplateVariableRegistry.specs.length);
    for (final button in buttons) {
      expect(TemplateVariableRegistry.canonical(button.key), button.key,
          reason: 'الزر يحمل مرادفًا لا مفتاحًا قانونيًا: ${button.key}');
      expect(button.label, TemplateVariableRegistry.arabicName(button.key));
    }
  });

  test('متغير غير معروف لا يُخمَّن له اسم', () {
    expect(TemplateVariableRegistry.isKnown('nope_xyz'), isFalse);
    expect(TemplateVariableRegistry.arabicName('nope_xyz'), 'متغير غير معروف');
    expect(TemplateVariableRegistry.canonical('nope_xyz'), isNull);
  });
}
