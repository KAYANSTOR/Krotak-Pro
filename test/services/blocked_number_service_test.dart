import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_blocked_number_service.dart';

void main() {
  group('LocalBlockedNumberService', () {
    late _MemSettings settings;
    late LocalBlockedNumberService service;

    setUp(() {
      settings = _MemSettings();
      service = LocalBlockedNumberService(
        settings: settings,
        clock: FixedClock(DateTime.utc(2026, 9, 20)),
      );
    });

    test('adds canonical form and matches variants', () async {
      final added = await service.add('0777123456');
      expect(added, isA<Success<void>>());
      expect(await service.isBlocked('777123456'), isTrue);
      expect(await service.isBlocked('+967777123456'), isTrue);
      expect(await service.isBlocked('733000000'), isFalse);
      expect(await service.list(), ['777123456']);
    });

    test('hitsRawEvent matches sender before parse', () async {
      await service.add('777123456');
      expect(
        await service.hitsRawEvent(sourceKey: '0777123456', body: 'hello'),
        isTrue,
      );
      expect(
        await service.hitsRawEvent(
          sourceKey: 'JIB',
          body: 'حوالة 1000 إلى 777123456 مرجع 9',
        ),
        isTrue,
      );
      expect(
        await service.hitsRawEvent(sourceKey: 'JIB', body: 'حوالة 1000'),
        isFalse,
      );
    });

    test('remove drops the number', () async {
      await service.add('777123456');
      await service.remove('+967777123456');
      expect(await service.isBlocked('777123456'), isFalse);
    });
  });
}

final class _MemSettings implements SettingsRepository {
  final values = <String, String>{};

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final v = values[key];
    if (v == null) return const Success(null);
    return Success(
      AppSetting(key: key, value: v, updatedAt: DateTime.utc(2026, 9, 20)),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}
