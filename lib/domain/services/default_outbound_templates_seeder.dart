import 'dart:convert';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';
import 'outbound_template_catalog.dart';

/// يزرع النصوص الأولية لكل قالب صادر معرّف في [OutboundTemplateCatalog].
///
/// الزرع هو التهيئة الوحيدة المسموح فيها باستخدام النص الافتراضي. قبل الزرع
/// نرحّل بيانات القوالب المخصصة من الإصدارات السابقة، مع الحفاظ على نص النظام.
final class DefaultOutboundTemplatesSeeder {
  const DefaultOutboundTemplatesSeeder({
    required this.settings,
    required this.clock,
  });

  final SettingsRepository settings;
  final Clock clock;

  /// Bump when new catalog keys are added so existing installs backfill.
  static const seededKey = 'default_outbound_templates_seeded_v7';

  static const _legacyPosCustomerTemplateWithoutCategory =
      'شبكة {NETWORK_NAME}\n{cards}';
  static const _legacyPosCustomerTemplateWithValue =
      'شبكة {NETWORK_NAME}\nالفئة: {CARD_VALUE} {CURRENCY}\n{cards}';

  static Map<String, String> catalog() => OutboundTemplateCatalog.initialBodies();

  Future<Result<void>> seedIfNeeded() async {
    final migrated = await _migrateLegacyCustomTemplates();
    if (migrated is Failure<void>) return migrated;

    final defaults = catalog();
    for (final e in defaults.entries) {
      final existing = await settings.find(e.key);
      if (existing is Failure<AppSetting?>) return Failure(existing.error);
      final value = (existing as Success<AppSetting?>).value?.value.trim();
      if (value != null && value.isNotEmpty) {
        final legacy = _migrateKnownLegacy(e.key, value);
        if (legacy != null && legacy != value) {
          final saved = await settings.save(
            AppSetting(key: e.key, value: legacy, updatedAt: clock.now()),
          );
          if (saved is Failure<void>) return Failure(saved.error);
        }
        continue;
      }
      final saved = await settings.save(
        AppSetting(key: e.key, value: e.value, updatedAt: clock.now()),
      );
      if (saved is Failure<void>) return Failure(saved.error);
    }

    final seeded = await settings.save(
      AppSetting(key: seededKey, value: 'true', updatedAt: clock.now()),
    );
    if (seeded is Failure<void>) return Failure(seeded.error);
    return const Success(null);
  }

  /// Idempotently migrates old `custom:<id>`/JSON bodies and restores the system
  /// template that old activation code temporarily replaced.
  Future<Result<void>> _migrateLegacyCustomTemplates() async {
    final registryResult = await settings.find(SettingKeys.customOutboundTemplates);
    if (registryResult is Failure<AppSetting?>) return Failure(registryResult.error);
    final activeResult = await settings.find(SettingKeys.activeOutboundTemplates);
    if (activeResult is Failure<AppSetting?>) return Failure(activeResult.error);

    final entries = <Map<String, dynamic>>[];
    final rawRegistry = (registryResult as Success<AppSetting?>).value?.value;
    if (rawRegistry != null && rawRegistry.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawRegistry);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              try {
                entries.add(Map<String, dynamic>.from(item));
              } on TypeError {
                // Preserve malformed legacy entry; skip only its migration.
              }
            }
          }
        }
      } on FormatException {
        // Keep a corrupt legacy registry untouched; it must not block startup.
      }
    }

    final active = <String, String>{};
    final rawActive = (activeResult as Success<AppSetting?>).value?.value;
    if (rawActive != null && rawActive.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawActive);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is String && entry.value is String) {
              active[entry.key as String] = entry.value as String;
            }
          }
        }
      } on FormatException {
        // A malformed activation map cannot safely identify a legacy override.
      }
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final entry in entries) {
      final id = entry['id'];
      if (id is String && id.trim().isNotEmpty) byId[id.trim()] = entry;
    }
    // An active custom body may outlive a damaged or removed metadata row.
    // Preserve its text anyway so the active pointer does not become a dead link.
    for (final activation in active.entries) {
      byId.putIfAbsent(
        activation.value,
        () => <String, dynamic>{'id': activation.value, 'target': activation.key},
      );
    }

    for (final item in byId.entries) {
      final id = item.key;
      final newKey = SettingKeys.customOutboundBody(id);
      final current = await settings.find(newKey);
      if (current is Failure<AppSetting?>) return Failure(current.error);
      final currentBody = (current as Success<AppSetting?>).value?.value.trim();
      if (currentBody != null && currentBody.isNotEmpty) continue;

      String? legacyBody;
      final oldKeyResult = await settings.find(
        SettingKeys.legacyCustomOutboundBody(id),
      );
      if (oldKeyResult is Failure<AppSetting?>) return Failure(oldKeyResult.error);
      legacyBody = (oldKeyResult as Success<AppSetting?>).value?.value;
      if (legacyBody == null || legacyBody.trim().isEmpty) {
        final body = item.value['body'];
        if (body is String && body.trim().isNotEmpty) legacyBody = body;
      }
      if (legacyBody == null || legacyBody.trim().isEmpty) {
        for (final activation in active.entries) {
          if (activation.value == id) {
            final system = await settings.find(activation.key);
            if (system is Failure<AppSetting?>) return Failure(system.error);
            legacyBody = (system as Success<AppSetting?>).value?.value;
            break;
          }
        }
      }
      if (legacyBody == null || legacyBody.trim().isEmpty) continue;
      final saved = await settings.save(
        AppSetting(key: newKey, value: legacyBody, updatedAt: clock.now()),
      );
      if (saved is Failure<void>) return Failure(saved.error);
    }

    for (final activation in active.entries) {
      final originalKey = SettingKeys.outboundSystemOriginal(activation.key);
      final originalResult = await settings.find(originalKey);
      if (originalResult is Failure<AppSetting?>) return Failure(originalResult.error);
      final original = (originalResult as Success<AppSetting?>).value?.value;
      if (original != null && original.trim().isNotEmpty) {
        final currentResult = await settings.find(activation.key);
        if (currentResult is Failure<AppSetting?>) return Failure(currentResult.error);
        final current = (currentResult as Success<AppSetting?>).value?.value;
        if (current != original) {
          final restored = await settings.save(
            AppSetting(key: activation.key, value: original, updatedAt: clock.now()),
          );
          if (restored is Failure<void>) return Failure(restored.error);
        }
        // Tombstone the legacy snapshot so later operator edits are not overwritten.
        final cleared = await settings.save(
          AppSetting(key: originalKey, value: '', updatedAt: clock.now()),
        );
        if (cleared is Failure<void>) return Failure(cleared.error);
        continue;
      }

      // Older records may have no saved original. Restore the catalog body only
      // when the system value is exactly the active custom body; never clobber
      // a distinct operator-edited system template.
      final currentResult = await settings.find(activation.key);
      if (currentResult is Failure<AppSetting?>) return Failure(currentResult.error);
      final current = (currentResult as Success<AppSetting?>).value?.value;
      final customResult = await settings.find(
        SettingKeys.customOutboundBody(activation.value),
      );
      if (customResult is Failure<AppSetting?>) return Failure(customResult.error);
      final customBody = (customResult as Success<AppSetting?>).value?.value;
      final definition = OutboundTemplateCatalog.byKey(activation.key);
      if (current != null && current == customBody && definition != null) {
        final restored = await settings.save(
          AppSetting(
            key: activation.key,
            value: definition.initialBody,
            updatedAt: clock.now(),
          ),
        );
        if (restored is Failure<void>) return Failure(restored.error);
      }
    }
    return const Success(null);
  }

  String? _migrateKnownLegacy(String key, String current) {
    if (key != SettingKeys.posCustomerCardDeliveryTemplate) return null;
    final normalized = current.replaceAll('\r\n', '\n').trim();
    if (normalized == _legacyPosCustomerTemplateWithoutCategory.trim() ||
        normalized == _legacyPosCustomerTemplateWithValue.trim()) {
      return OutboundTemplateCatalog.initialBodies()[key];
    }
    return null;
  }
}
