import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// تفعيل قالب رسالة مخصّص بدلًا من قالب النظام.
///
/// **مصدران لا يتنافسان:**
/// - قرار «أي قالب يُرسل» → [SettingKeys.activeOutboundTemplates] (مفتاح نظام ← معرّف قالب مخصّص).
/// - نص القالب المخصّص → [SettingKeys.customOutboundBody] وحده.
///
/// قالب النظام **لا يُكتب فوقه أبدًا**، فيبقى نصه الأصلي سليمًا ويعود تلقائيًا
/// بمجرّد رفع القرار من الخريطة. لذلك:
/// - التفعيل = كتابة واحدة للخريطة (بعد التحقق من وجود نص القالب).
/// - الإلغاء = كتابة واحدة للخريطة.
///
/// لا توجد حالة نصف مكتملة: لا كتابة على مفتاح قالب النظام، ولا نسخة «أصلية»
/// موازية يمكن أن تنحرف عن النص الحقيقي.
final class OutboundTemplateActivation {
  const OutboundTemplateActivation({required this.settings, required this.clock});

  final SettingsRepository settings;
  final Clock clock;

  /// systemKey → customId لكل استبدال فعّال حالياً.
  Future<Map<String, String>> loadActive() async {
    final r = await settings.find(SettingKeys.activeOutboundTemplates);
    final raw = r is Success<AppSetting?> ? r.value?.value : null;
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, String>{
          for (final e in decoded.entries)
            if (e.key is String &&
                e.value is String &&
                (e.value as String).isNotEmpty)
              e.key as String: e.value as String,
        };
      }
    } on FormatException {
      // سجل تالف: نعامله كأنه فارغ (كل القوالب الافتراضية فعّالة).
    }
    return <String, String>{};
  }

  /// يجعل نص القالب المخصّص [customId] هو المُرسَل بدل قالب [systemKey].
  ///
  /// يتحقق أولًا من أن نص القالب المخصّص مكتوب فعلًا، فلا تُكتب خريطة تفعيل
  /// تشير إلى قالب غير موجود (وهو ما كان يُنتج حالة جزئية).
  Future<Result<void>> activate({
    required String systemKey,
    required String customId,
  }) async {
    final body = await settings.find(SettingKeys.customOutboundBody(customId));
    if (body is Failure<AppSetting?>) return Failure(body.error);
    final value = (body as Success<AppSetting?>).value?.value.trim() ?? '';
    if (value.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'template_empty',
          message: 'لا يمكن تفعيل قالب بلا نص — احفظ نص القالب أولًا',
        ),
      );
    }
    final active = await loadActive();
    active[systemKey] = customId;
    return _writeActive(active);
  }

  /// يلغي الاستبدال: يعود قالب النظام هو المُرسَل.
  Future<Result<void>> revert({required String systemKey}) async {
    final active = await loadActive();
    if (!active.containsKey(systemKey)) return const Success(null);
    active.remove(systemKey);
    return _writeActive(active);
  }

  /// يُعيد كل القوالب لنصوص النظام (يُستخدم قبل «إصلاح القوالب»).
  Future<Result<void>> clear() => _writeActive(<String, String>{});

  Future<Result<void>> _writeActive(Map<String, String> active) => settings.save(
        AppSetting(
          key: SettingKeys.activeOutboundTemplates,
          value: jsonEncode(active),
          updatedAt: clock.now(),
        ),
      );
}
