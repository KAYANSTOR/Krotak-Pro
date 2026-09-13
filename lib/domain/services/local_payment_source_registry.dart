import 'dart:convert';
import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/payment_event.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

final class LocalPaymentSourceRegistry {
  LocalPaymentSourceRegistry({required this.settings, required this.clock});
  final SettingsRepository settings;
  final Clock clock;

  Future<Result<List<PaymentSource>>> list() async {
    final result = await settings.find(SettingKeys.notificationSources);
    if (result is Failure<AppSetting?>) return Failure(result.error);
    final raw = (result as Success<AppSetting?>).value?.value;
    if (raw == null || raw.trim().isEmpty) return const Success([]);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const Failure(AppError('notification_sources_invalid'));
      return Success(decoded.whereType<Map>().map(_fromJson).whereType<PaymentSource>().toList(growable: false));
    } catch (_) {
      return const Failure(AppError('notification_sources_invalid'));
    }
  }

  Future<Result<void>> upsert({required String displayName, required String packageName, required bool enabled}) async {
    final name = displayName.trim();
    final package = packageName.trim();
    if (name.isEmpty || package.isEmpty || package.contains(RegExp(r'\s'))) {
      return const Failure(AppError('notification_source_invalid'));
    }
    final current = await list();
    if (current is Failure<List<PaymentSource>>) return Failure(current.error);
    final source = PaymentSource(id: 'notification:$package', displayName: name, channel: PaymentChannel.notification, packageName: package, enabled: enabled);
    final next = [...(current as Success<List<PaymentSource>>).value]..removeWhere((s) => s.id == source.id)..add(source);
    return _save(next);
  }

  Future<Result<void>> setEnabled(String packageName, bool enabled) async {
    final current = await list();
    if (current is Failure<List<PaymentSource>>) return Failure(current.error);
    final next = (current as Success<List<PaymentSource>>).value.map((s) => s.packageName == packageName
        ? PaymentSource(id: s.id, displayName: s.displayName, channel: s.channel, packageName: s.packageName, smsSenderHint: s.smsSenderHint, enabled: enabled)
        : s).toList(growable: false);
    return _save(next);
  }

  Future<Result<void>> remove(String packageName) async {
    final current = await list();
    if (current is Failure<List<PaymentSource>>) return Failure(current.error);
    return _save((current as Success<List<PaymentSource>>).value.where((s) => s.packageName != packageName).toList(growable: false));
  }

  Future<Result<void>> _save(List<PaymentSource> sources) => settings.save(AppSetting(key: SettingKeys.notificationSources, value: jsonEncode(sources.map((s) => {
    'id': s.id,
    'displayName': s.displayName,
    'channel': 'notification',
    'packageName': s.packageName,
    'smsSenderHint': s.smsSenderHint,
    'enabled': s.enabled,
  }).toList(growable: false)), updatedAt: clock.now()));

  PaymentSource? _fromJson(Map raw) {
    final id = raw['id']?.toString(), name = raw['displayName']?.toString(), package = raw['packageName']?.toString();
    if (id == null || name == null || package == null || package.isEmpty) return null;
    return PaymentSource(id: id, displayName: name, channel: PaymentChannel.notification, packageName: package, smsSenderHint: raw['smsSenderHint']?.toString(), enabled: raw['enabled'] == true);
  }
}
