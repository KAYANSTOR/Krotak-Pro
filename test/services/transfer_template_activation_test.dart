import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_transfer_template_activation_service.dart';

TransferTemplate _tpl({
  required String id,
  required bool active,
  String? walletId,
  String? posId,
  String? senderCode,
}) {
  return TransferTemplate(
    id: id,
    name: id,
    pattern: 'تحويل {amount} الى {phone}',
    isActive: active,
    walletId: walletId,
    posId: posId,
    senderCode: senderCode,
  );
}

void main() {
  late _MemTemplates repo;
  late LocalTransferTemplateActivationService service;

  setUp(() {
    repo = _MemTemplates();
    service = LocalTransferTemplateActivationService(repo);
  });

  test('saving an active template keeps sibling templates active', () async {
    await repo.save(_tpl(id: 'a', active: true, posId: 'pos-1'));
    await repo.save(_tpl(id: 'b', active: true, posId: 'pos-1'));
    await repo.save(_tpl(id: 'c', active: true, posId: 'pos-1'));

    final r = await service.save(_tpl(id: 'a', active: true, posId: 'pos-1'));
    expect(r, isA<Success<void>>());

    // كانت المشكلة هنا: تفعيل قالب واحد كان يُوقف بقية قوالب نفس نقطة البيع.
    for (final id in ['a', 'b', 'c']) {
      expect((await repo.findById(id) as Success).value!.isActive, isTrue);
    }
  });

  test('setGroupActive activates or deactivates a whole source', () async {
    await repo.save(_tpl(id: 'p1', active: true, posId: 'pos-1'));
    await repo.save(_tpl(id: 'p2', active: false, posId: 'pos-1'));
    await repo.save(_tpl(id: 'w', active: true, walletId: 'w1'));

    final off = await service.setGroupActive(key: 'pos:pos-1', isActive: false);
    expect(off, isA<Success<int>>());
    expect((off as Success<int>).value, 1);
    expect((await repo.findById('p1') as Success).value!.isActive, isFalse);

    final on = await service.setGroupActive(key: 'pos:pos-1', isActive: true);
    expect(on, isA<Success<int>>());
    expect((on as Success<int>).value, 2);
    expect((await repo.findById('p2') as Success).value!.isActive, isTrue);
    // محفظة أخرى لا تتأثر.
    expect((await repo.findById('w') as Success).value!.isActive, isTrue);
  });

  test('setGroupActive writes nothing when already in target state', () async {
    await repo.save(_tpl(id: 'p1', active: true, posId: 'pos-1'));

    final r = await service.setGroupActive(key: 'pos:pos-1', isActive: true);
    expect(r, isA<Success<int>>());
    expect((r as Success<int>).value, 0);
    expect(repo.saveCount, 1);
  });

  test('groupCounts reports active versus total for one source', () async {
    await repo.save(_tpl(id: 'p1', active: true, posId: 'pos-1'));
    await repo.save(_tpl(id: 'p2', active: false, posId: 'pos-1'));
    await repo.save(_tpl(id: 'p3', active: true, posId: 'pos-2'));
    await repo.save(_tpl(id: 'w', active: false, walletId: 'w1'));

    final r = await service.groupCounts('pos:pos-1');
    expect(r, isA<Success<({int active, int total})>>());
    final counts = (r as Success<({int active, int total})>).value;
    expect(counts.active, 1);
    expect(counts.total, 2);
  });

  test('groupKey prefers pos over wallet over sender', () {
    expect(
      LocalTransferTemplateActivationService.groupKey(
        _tpl(id: 'x', active: true, posId: 'p', walletId: 'w', senderCode: 's'),
      ),
      'pos:p',
    );
    expect(
      LocalTransferTemplateActivationService.groupKey(
        _tpl(id: 'x', active: true, walletId: 'w', senderCode: 's'),
      ),
      'wallet:w',
    );
    expect(
      LocalTransferTemplateActivationService.groupKey(
        _tpl(id: 'x', active: true, senderCode: 'Jeeb'),
      ),
      'sender:jeeb',
    );
    expect(
      LocalTransferTemplateActivationService.groupKey(_tpl(id: 'x', active: true)),
      'unscoped',
    );
  });
}

final class _MemTemplates implements TransferTemplateRepository {
  final list = <TransferTemplate>[];
  int saveCount = 0;

  @override
  Future<Result<List<TransferTemplate>>> listAll() async => Success(List.of(list));

  @override
  Future<Result<List<TransferTemplate>>> listByWallet(String? walletId) async =>
      Success(list.where((t) => t.walletId == walletId).toList());

  @override
  Future<Result<TransferTemplate?>> findById(String id) async {
    for (final t in list) {
      if (t.id == id) return Success(t);
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> save(TransferTemplate template) async {
    saveCount += 1;
    list.removeWhere((t) => t.id == template.id);
    list.add(template);
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    list.removeWhere((t) => t.id == id);
    return const Success(null);
  }
}
