import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// تفعيل قالب رسالة مخصّص مكان قالب النظام.
///
/// كل مسارات الإرسال تقرأ مفتاح قالب النظام مباشرة، لذا يكون التفعيل
/// «كتابة نافذة»: نص القالب المخصّص يُكتب تحت مفتاح النظام نفسه، ويُحفظ
/// نص النظام الأصلي جانباً ليعود عند إلغاء التفعيل. السجل
/// [SettingKeys.activeOutboundTemplates] هو مصدر الحقيقة لمن هو الفعّال.
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
            if (e.key is String && e.value is String && (e.value as String).isNotEmpty)
              e.key as String: e.value as String,
        };
      }
    } on FormatException {
      // سجل تالف: نعامله كأنه فارغ (كل القوالب الافتراضية فعّالة).
    }
    return <String, String>{};
  }

  /// نص قالب النظام الأصلي المحفوظ أثناء الاستبدال (أو null).
  Future<String?> originalBody(String systemKey) async {
    final r = await settings.find(SettingKeys.outboundSystemOriginal(systemKey));
    final v = r is Success<AppSetting?> ? r.value?.value : null;
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  /// يجعل [customBody] هو النص المُرسَل فعلياً بدل قالب [systemKey].
  Future<Result<void>> activate({
    required String systemKey,
    required String customId,
    required String customBody,
    required String systemFallback,
  }) async {
    final body = customBody.trim();
    if (body.isEmpty) {
      return const Failure(AppFailure(code: 'template_empty', message: 'لا يمكن تفعيل قالب فارغ'));
    }
    final active = await loadActive();
    if (!active.containsKey(systemKey)) {
      // أول استبدال: احفظ النص الحالي (قد يكون المشغّل عدّله) ليعود لاحقاً.
      final cur = await settings.find(systemKey);
      final current = cur is Success<AppSetting?> ? cur.value?.value : null;
      final saved = await _save(
        SettingKeys.outboundSystemOriginal(systemKey),
        (current == null || current.trim().isEmpty) ? systemFallback : current,
      );
      if (saved is Failure<void>) return saved;
    }
    final wrote = await _save(systemKey, body);
    if (wrote is Failure<void>) return wrote;
    active[systemKey] = customId;
    return _writeActive(active);
  }

  /// يلغي الاستبدال: يعود قالب النظام الأصلي هو المُرسَل.
  Future<Result<void>> revert({
    required String systemKey,
    required String systemFallback,
  }) async {
    final active = await loadActive();
    if (!active.containsKey(systemKey)) return const Success(null);
    final restored = await _save(systemKey, await originalBody(systemKey) ?? systemFallback);
    if (restored is Failure<void>) return restored;
    active.remove(systemKey);
    return _writeActive(active);
  }

  /// يُعيد كل القوالب لنصوص النظام (يُستخدم قبل «إصلاح القوالب»).
  Future<Result<void>> clear() => _writeActive(<String, String>{});

  /// حفظ تعديل على قالب نظام: إن كان مستبدلاً يُحفظ كنص أصلي ولا يمسّ المُرسَل.
  Future<Result<void>> saveSystemBody(String systemKey, String body) async {
    final active = await loadActive();
    if (active.containsKey(systemKey)) {
      return _save(SettingKeys.outboundSystemOriginal(systemKey), body);
    }
    return _save(systemKey, body);
  }

  /// بعد تعديل قالب مخصّص فعّال: يُحدَّث النص المُرسَل فعلياً أيضاً.
  Future<Result<void>> syncActiveBody(String systemKey, String customId, String body) async {
    final active = await loadActive();
    if (active[systemKey] != customId) return const Success(null);
    return _save(systemKey, body);
  }

  Future<Result<void>> _writeActive(Map<String, String> active) =>
      _save(SettingKeys.activeOutboundTemplates, jsonEncode(active));

  Future<Result<void>> _save(String key, String value) =>
      settings.save(AppSetting(key: key, value: value, updatedAt: clock.now()));
}
