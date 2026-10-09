import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/default_outbound_templates_seeder.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/outbound_template_renderer.dart';

final class _MemSettings implements SettingsRepository {
  _MemSettings([Map<String, String>? values])
      : values = values ?? <String, String>{};

  final Map<String, String> values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = values[key];
    return Success(
      value == null
          ? null
          : AppSetting(key: key, value: value, updatedAt: DateTime.utc(2026, 10, 9)),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}

/// النصوص الافتراضية المعتمدة من المالك حرفيًا (مرحلة A).
const approvedCardDeliveryBodies = <String, String>{
  SettingKeys.cardDeliveryCashTemplate:
      'كرتك من شبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}',
  SettingKeys.cardDeliveryCreditTemplate:
      'كرت آجل عليكم في حسابكم\nمن شبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}',
  SettingKeys.cardDeliveryGiftTemplate:
      'كرتك الهدية\nمن شبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}',
  SettingKeys.salafniCardDeliveryTemplate:
      'كرتك من خدمة سلفني\nشبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}',
  SettingKeys.depositNoStockTemplate:
      'عزيزي {اسم_الزبون_الاول}\nتم استلام {المبلغ}﷼\nسوف يتم مشاركة الكرت آلياً فور توفره',
};

void main() {
  test('كل قوالب إرسال الكروت مسجّلة في العقد المركزي بنصها المعتمد', () {
    for (final entry in approvedCardDeliveryBodies.entries) {
      final definition = OutboundTemplateCatalog.byKey(entry.key);
      expect(definition, isNotNull, reason: 'قالب غير مسجّل: ${entry.key}');
      expect(definition!.initialBody, entry.value, reason: entry.key);
    }
  });

  test('المتغيرات المطلوبة عربية وتُفرض قبل الإرسال', () {
    final cash = OutboundTemplateCatalog.byKey(SettingKeys.cardDeliveryCashTemplate)!;
    expect(
      cash.requiredVariables,
      containsAll(<String>['اسم_المحفظة', 'الفئة', 'الرقم', 'الرمز']),
    );
    final noStock = OutboundTemplateCatalog.byKey(SettingKeys.depositNoStockTemplate)!;
    expect(
      noStock.requiredVariables,
      containsAll(<String>['اسم_الزبون_الاول', 'المبلغ']),
    );
  });

  test('الزرع يكتب النصوص المعتمدة في الإعدادات', () async {
    final settings = _MemSettings();
    final result = await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: FixedClock(DateTime.utc(2026, 10, 9)),
    ).seedIfNeeded();
    expect(result, isA<Success<void>>());
    for (final entry in approvedCardDeliveryBodies.entries) {
      expect(settings.values[entry.key], entry.value, reason: entry.key);
    }
  });

  test('القالب المعتمد يُرسل بلا أي متغيّر غير محلول', () async {
    final settings = _MemSettings();
    await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: FixedClock(DateTime.utc(2026, 10, 9)),
    ).seedIfNeeded();
    final renderer = OutboundTemplateRenderer(settings: settings);

    final cash = await renderer.renderRegistered(
      key: SettingKeys.cardDeliveryCashTemplate,
      values: const {
        'اسم_المحفظة': 'Jaib',
        'الفئة': '100 ر.ي',
        'الرقم': '1234567',
        'الرمز': '987654',
      },
    );
    expect(cash, isA<Success<String>>());
    expect((cash as Success<String>).value, 'كرتك من شبكة Jaib\n100 ر.ي\n1234567\n987654');

    final noStock = await renderer.renderRegistered(
      key: SettingKeys.depositNoStockTemplate,
      values: const {'اسم_الزبون_الاول': 'عميل', 'المبلغ': '1000'},
    );
    expect(noStock, isA<Success<String>>());
    expect(
      (noStock as Success<String>).value,
      'عزيزي عميل\nتم استلام 1000﷼\nسوف يتم مشاركة الكرت آلياً فور توفره',
    );
  });

  test('لا يُرسل قالب إرسال كرت بلا تمرير متغيّراته المطلوبة', () async {
    final settings = _MemSettings();
    await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: FixedClock(DateTime.utc(2026, 10, 9)),
    ).seedIfNeeded();
    final renderer = OutboundTemplateRenderer(settings: settings);
    final result = await renderer.renderRegistered(
      key: SettingKeys.cardDeliveryCashTemplate,
      values: const {'اسم_المحفظة': 'Jaib'},
    );
    expect(result, isA<Failure<String>>());
    expect((result as Failure<String>).error.code, 'outbound_template_missing_value');
  });
}
