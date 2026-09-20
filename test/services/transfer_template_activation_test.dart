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

  test('activating one wallet template deactivates siblings', () async {
    await repo.save(_tpl(id: 'a', active: true, walletId: 'w1'));
    await repo.save(_tpl(id: 'b', active: true, walletId: 'w1'));
    await repo.save(_tpl(id: 'c', active: true, walletId: 'w2'));

    final r = await service.saveExclusive(
      _tpl(id: 'a', active: true, walletId: 'w1'),
    );
    expect(r, isA<Success<void>>());

    expect((await repo.findById('a') as Success).value!.isActive, isTrue);
    expect((await repo.findById('b') as Success).value!.isActive, isFalse);
    expect((await repo.findById('c') as Success).value!.isActive, isTrue);
  });

  test('activating a POS template does not touch wallet siblings', () async {
    await repo.save(_tpl(id: 'p1', active: true, posId: 'pos-1', walletId: 'w1'));
    await repo.save(_tpl(id: 'p2', active: true, posId: 'pos-1'));
    await repo.save(_tpl(id: 'w', active: true, walletId: 'w1'));

    final r = await service.saveExclusive(
      _tpl(id: 'p1', active: true, posId: 'pos-1', walletId: 'w1'),
    );
    expect(r, isA<Success<void>>());
    expect((await repo.findById('p2') as Success).value!.isActive, isFalse);
    expect((await repo.findById('w') as Success).value!.isActive, isTrue);
  });

  test('deactivating does not force another default', () async {
    await repo.save(_tpl(id: 'a', active: true, walletId: 'w1'));
    await repo.save(_tpl(id: 'b', active: false, walletId: 'w1'));

    final r = await service.saveExclusive(
      _tpl(id: 'a', active: false, walletId: 'w1'),
    );
    expect(r, isA<Success<void>>());
    expect((await repo.findById('a') as Success).value!.isActive, isFalse);
    expect((await repo.findById('b') as Success).value!.isActive, isFalse);
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
