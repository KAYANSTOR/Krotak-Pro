import 'dart:convert';

import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';
import 'outbound_template_catalog.dart';

/// محرّك القوالب الصادرة المركزي.
///
/// القاعدة الحاكمة: **لا إرسال بلا قالب مسجّل في الإعدادات.**
///
/// كل مسار إرسال في المنتج يمرّ من هنا. لا يوجد fallback نصي وقت التشغيل، ولا
/// نص افتراضي مخفي: القالب الافتراضي يُكتب مرة واحدة عند الزرع الأول
/// ([OutboundTemplateCatalog.initialBody])، وبعدها يصبح
/// `Settings → Outbound Message Templates` هو المصدر الوحيد للحقيقة.
///
/// الحالة الصحيحة:
/// ```text
/// Template exists in Settings → Validate → Render → Send
/// ```
/// والحالة الممنوعة (أصبحت مستحيلة):
/// ```text
/// Template missing → Fallback → Send
/// ```
final class OutboundTemplateRenderer {
  const OutboundTemplateRenderer({this.settings});

  final SettingsRepository? settings;

  /// مطابقة `{name}` — يُرفض أي توكن متبقٍّ بعد الاستبدال.
  static final RegExp placeholderPattern = RegExp(r'\{([^{}\s]+)\}');

  /// مطابقة `%name` — صيغة قديمة مدعومة، وتبقى غير المحلولة مرفوضة أيضًا.
  static final RegExp percentPlaceholderPattern =
      RegExp(r'%([A-Za-z][A-Za-z0-9_]*)');

  /// أسماء `{...}` الموجودة في النص.
  static Set<String> bracePlaceholders(String body) => placeholderPattern
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();

  /// أسماء `%...` الموجودة في النص.
  static Set<String> percentPlaceholders(String body) =>
      percentPlaceholderPattern.allMatches(body).map((m) => m.group(1)!).toSet();

  /// كل المتغيرات غير المحلولة — بالصيغتين.
  static List<String> unresolvedPlaceholders(String body) {
    final left = <String>{...bracePlaceholders(body), ...percentPlaceholders(body)};
    return left.toList(growable: false);
  }

  /// استبدال القيم (مفاتيح بلا أقواس). يدعم `{key}` و`%key`.
  static String substitute(String template, Map<String, String> values) {
    var result = template;
    for (final e in values.entries) {
      result = result.replaceAll('{${e.key}}', e.value);
      result = result.replaceAll('%${e.key}', e.value);
    }
    return result;
  }

  /// استبدال صارم: يفشل إن بقي أي متغير (بأي صيغة) أو كان الناتج فارغًا.
  static Result<String> renderStrict({
    required String template,
    required Map<String, String> values,
  }) {
    final body = substitute(template, values).trim();
    if (body.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'outbound_template_empty',
          message: 'نص القالب الناتج فارغ — لن يُرسل',
        ),
      );
    }
    final left = <String>{
      ...bracePlaceholders(body),
      ...percentPlaceholders(body),
    };
    if (left.isNotEmpty) {
      return Failure(
        AppFailure(
          code: 'outbound_unresolved_placeholder',
          message:
              'رفض الإرسال: متغيرات غير مستبدلة في القالب: ${left.map((e) => '{$e}').join(', ')}',
        ),
      );
    }
    return Success(body);
  }

  /// يقرأ نص القالب المسجّل من الإعدادات بلا أي بديل.
  ///
  /// كل حالة فشل صريحة، ولا يُعاد نص مُختلق مكان القالب الغائب:
  /// - مفتاح غير مسجّل في العقد → `outbound_template_unregistered`.
  /// - تعذّر قراءة الإعدادات → `outbound_template_settings_read_failed`.
  /// - المفتاح غير مزروع أو قيمته فارغة → `outbound_template_missing`.
  Future<Result<String>> loadRegisteredBody(String key) async {
    final definition = OutboundTemplateCatalog.byKey(key);
    if (definition == null) {
      return Failure(
        AppFailure(
          code: 'outbound_template_unregistered',
          message: 'قالب غير مسجّل في مركز القوالب: $key',
        ),
      );
    }
    final repo = settings;
    if (repo == null) {
      return const Failure(
        AppFailure(
          code: 'outbound_template_settings_unavailable',
          message: 'تعذّر الوصول إلى الإعدادات — لا يمكن قراءة القالب، ولن يُرسل شيء',
        ),
      );
    }
    // أولًا: هل يوجد قالب مخصّص فعّال بدلًا من قالب النظام؟ القرار يقرأ من
    // خريطة التفعيل، والنص يُقرأ من مصدره الوحيد (لا نسخة موازية).
    final activeResult = await _activeCustomId(key);
    if (activeResult is Failure<String?>) return Failure(activeResult.error);
    final customId = (activeResult as Success<String?>).value;
    if (customId != null) {
      final custom =
          await repo.find(SettingKeys.customOutboundBody(customId));
      if (custom is Failure<AppSetting?>) {
        return Failure(
          AppFailure(
            code: 'outbound_template_settings_read_failed',
            message: 'تعذّر قراءة القالب المخصّص: ${custom.error.message}',
          ),
        );
      }
      final customBody = (custom as Success<AppSetting?>).value?.value.trim();
      if (customBody != null && customBody.isNotEmpty) {
        return Success(customBody);
      }
      // مؤشر تفعيل مكسور (القالب حُذف): نعود لقالب النظام المسجّل في
      // الإعدادات — وهو قالب مسجّل أيضًا، فلا نص مُختلق.
    }

    final found = await repo.find(key);
    if (found is Failure<AppSetting?>) {
      return Failure(
        AppFailure(
          code: 'outbound_template_settings_read_failed',
          message: 'تعذّر قراءة القالب من الإعدادات: ${found.error.message}',
        ),
      );
    }
    final value = (found as Success<AppSetting?>).value?.value.trim();
    if (value == null || value.isEmpty) {
      return Failure(
        AppFailure(
          code: 'outbound_template_missing',
          message:
              'القالب «${definition.title}» غير موجود في قوالب الرسائل — افتح الإعدادات وأنشئه قبل الإرسال',
        ),
      );
    }
    return Success(value);
  }

  /// معرّف القالب المخصّص الفعّال لهذا المفتاح، أو null.
  Future<Result<String?>> _activeCustomId(String systemKey) async {
    final repo = settings;
    if (repo == null) return const Success(null);
    final stored = await repo.find(SettingKeys.activeOutboundTemplates);
    if (stored is Failure<AppSetting?>) {
      return Failure(
        AppFailure(
          code: 'outbound_template_settings_read_failed',
          message: 'تعذّر قراءة سجل التفعيل: ${stored.error.message}',
        ),
      );
    }
    final raw = (stored as Success<AppSetting?>).value?.value;
    if (raw == null || raw.trim().isEmpty) return const Success(null);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final id = decoded[systemKey];
        if (id is String && id.trim().isNotEmpty) return Success(id.trim());
      }
    } on FormatException {
      // سجل تالف يُعامل كغير فعّال — لا يُوقف الإرسال بقالب النظام.
    }
    return const Success(null);
  }

  /// نقطة الإرسال الوحيدة: قالب مسجّل + نص من الإعدادات + تحقق + استبدال صارم.
  ///
  /// [values] يجب أن تغطي متغيرات القالب المطلوبة؛ أي نقص أو متغير غير معروف
  /// في نص القالب يُرجع Failure ولا يُرسل شيء.
  Future<Result<String>> renderRegistered({
    required String key,
    required Map<String, String> values,
  }) async {
    final definition = OutboundTemplateCatalog.byKey(key);
    if (definition == null) {
      return Failure(
        AppFailure(
          code: 'outbound_template_unregistered',
          message: 'قالب غير مسجّل في مركز القوالب: $key',
        ),
      );
    }
    final loaded = await loadRegisteredBody(key);
    if (loaded is Failure<String>) return loaded;
    final template = (loaded as Success<String>).value;

    // متغيرات القالب يجب أن تكون معروفة في العقد المركزي.
    final declared = <String>{
      ...bracePlaceholders(template),
      ...percentPlaceholders(template),
    };
    final unknown = declared.difference(definition.variables);
    if (unknown.isNotEmpty) {
      return Failure(
        AppFailure(
          code: 'outbound_template_unknown_variable',
          message:
              'القالب «${definition.title}» يستخدم متغيرات غير معروفة: ${unknown.map((e) => '{$e}').join(', ')}',
        ),
      );
    }

    // القيم المطلوبة يجب أن تُمرَّر من مسار الإرسال، وإلا استحال حلّ القالب
    // لو استخدمها المشغّل. (لا نشترط ظهور المتغير في النص: هذا قرار المشغّل.)
    final missingValues = definition.requiredVariables
        .where((name) => !values.containsKey(name))
        .toList(growable: false);
    if (missingValues.isNotEmpty) {
      return Failure(
        AppFailure(
          code: 'outbound_template_missing_value',
          message:
              'قيم ناقصة لإرسال «${definition.title}»: ${missingValues.join(', ')}',
        ),
      );
    }

    return renderStrict(template: template, values: values);
  }

  /// نص تسليم الكرت — يمرّ من القاعدة المركزية بلا بديل.
  ///
  /// [channel] يختار قالب نوع العملية (نقدي/آجل/هدية/سلفني). إن لم يُزرع
  /// القالب بعد، يُستخدم [fallbackKey] ثم قالب التسليم العام حتى لا ينقطع
  /// الإرسال عن تخصيص المشغّل القديم.
  Future<Result<String>> renderVoucherDelivery({
    required String serialNumber,
    required String secretCode,
    String cardValue = 'غير محدد',
    String? networkName,
    String currency = 'ر.ي',
    CardDeliveryChannel channel = CardDeliveryChannel.legacy,
    String? fallbackKey,
    Map<String, String> extraValues = const {},
  }) async {
    final serial = serialNumber.trim();
    final secret = secretCode.trim();
    var resolvedNetworkName = networkName?.trim() ?? '';
    if (resolvedNetworkName.isEmpty && settings != null) {
      final stored = await settings!.find(SettingKeys.networkName);
      if (stored is Success<AppSetting?>) {
        resolvedNetworkName = stored.value?.value.trim() ?? '';
      }
    }
    if (resolvedNetworkName.isEmpty) {
      resolvedNetworkName = SettingDefaults.networkName;
    }
    // 'الفئة' الفارغة تُعرض «غير محدد» لا نصًّا فارغًا.
    final resolvedCardValue =
        cardValue.trim().isEmpty ? 'غير محدد' : cardValue.trim();

    // المتغيرات العربية (aliases) تُمرَّر بنفس قيمة نظيرها الإنجليزي: تعريفها في
    // عقد القوالب وحده لا يكفي، لأن المحرك يستبدل ما وُجدت له قيمة فقط.
    final values = <String, String>{
      'serial': serial,
      'serial_number': serial,
      'الرقم': serial,
      'code': secret,
      'secret': secret,
      'الرمز': secret,
      'CARD_CODE': serial,
      'CARD_SERIAL': serial,
      'CARD_VALUE': resolvedCardValue,
      'الفئة': resolvedCardValue,
      'NETWORK_NAME': resolvedNetworkName,
      'network': resolvedNetworkName,
      'network_name': resolvedNetworkName,
      'اسم_المحفظة': resolvedNetworkName,
      'CURRENCY': currency,
      ...extraValues,
    };
    final preferred = channel.templateKey;
    if (preferred != null) {
      final specific = await renderRegistered(key: preferred, values: values);
      if (specific is Success<String>) return specific;
      if (specific is Failure<String> &&
          specific.error.code != 'outbound_template_missing') {
        return specific;
      }
    }
    return renderRegistered(
      key: fallbackKey ?? SettingKeys.voucherDeliverySmsTemplate,
      values: values,
    );
  }
}

/// نوع عملية صرف الكرت الذي يحدد قالب الرسالة الصادرة.
enum CardDeliveryChannel {
  legacy,
  cash,
  credit,
  gift,
  salafni;

  String? get templateKey => switch (this) {
        CardDeliveryChannel.legacy => null,
        CardDeliveryChannel.cash => SettingKeys.cardDeliveryCashTemplate,
        CardDeliveryChannel.credit => SettingKeys.cardDeliveryCreditTemplate,
        CardDeliveryChannel.gift => SettingKeys.cardDeliveryGiftTemplate,
        CardDeliveryChannel.salafni => SettingKeys.salafniCardDeliveryTemplate,
      };
}
