import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/template_performance_service.dart';

void main() {
  late _MemSettings settings;
  late TemplatePerformanceService service;
  final fixed = DateTime.utc(2026, 9, 22, 12);

  setUp(() {
    settings = _MemSettings();
    service = TemplatePerformanceService(settings: settings, now: () => fixed);
  });

  TransferTemplate tpl(String id, String name, {bool active = true}) {
    return TransferTemplate(
      id: id,
      name: name,
      pattern: 'pattern-$id',
      isActive: active,
    );
  }

  test('counts matches per template and sorts by frequency', () async {
    await service.recordMatch('a');
    await service.recordMatch('b');
    await service.recordMatch('a');

    final rows = await service.snapshot([
      tpl('a', 'Alpha'),
      tpl('b', 'Beta'),
      tpl('c', 'Gamma', active: false),
    ]);

    expect(rows.first.templateId, 'a');
    expect(rows.first.matchCount, 2);
    expect(rows.first.lastMatchedAt, fixed);
    expect(rows[1].templateId, 'b');
    expect(rows[1].matchCount, 1);
    expect(rows[2].templateId, 'c');
    expect(rows[2].matchCount, 0);
  });

  test('empty template id is counted as unmatched', () async {
    await service.recordMatch('  ');
    await service.recordUnmatched();
    final rows = await service.snapshot(const []);
    expect(rows, hasLength(1));
    expect(rows.single.unmatched, isTrue);
    expect(rows.single.matchCount, 2);
  });

  test('survives settings round-trip JSON', () async {
    await service.recordMatch('wallet-1');
    final again = TemplatePerformanceService(settings: settings, now: () => fixed);
    final rows = await again.snapshot([tpl('wallet-1', 'جيب')]);
    expect(rows.single.matchCount, 1);
  });
}

final class _MemSettings implements SettingsRepository {
  final Map<String, AppSetting> store = {};

  @override
  Future<Result<AppSetting?>> find(String key) async => Success(store[key]);

  @override
  Future<Result<void>> save(AppSetting setting) async {
    store[setting.key] = setting;
    return const Success(null);
  }
}
