import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/default_pos_templates_seeder.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_message_parser.dart';

class _MemTemplates implements TransferTemplateRepository {
  final map = <String, TransferTemplate>{};

  @override
  Future<Result<List<TransferTemplate>>> listAll() async =>
      Success(map.values.toList());

  @override
  Future<Result<List<TransferTemplate>>> listByWallet(String? walletId) async =>
      Success(map.values.where((t) => t.walletId == walletId).toList());

  @override
  Future<Result<TransferTemplate?>> findById(String id) async =>
      Success(map[id]);

  @override
  Future<Result<void>> save(TransferTemplate template) async {
    map[template.id] = template;
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    map.remove(id);
    return const Success(null);
  }
}

void main() {
  test('seeds exactly three default inbound POS templates', () async {
    final repo = _MemTemplates();
    final seeded = await DefaultPosTemplatesSeeder(templates: repo).seedForPos(
      posId: 'pos-1',
      posName: 'نقطة',
    );
    expect(seeded, isA<Success<int>>());
    expect((seeded as Success<int>).value, 3);
    expect(repo.map.length, 3);
    expect(
      repo.map.values.map((t) => t.name).toSet(),
      {
        'إرسال كروت إلى نقطة البيع',
        'إرسال كروت إلى عميل نقطة البيع',
        'استعلام رصيد نقطة البيع',
      },
    );
    final customerTemplate = repo.map['tpl-pos-pos-1-cards-to-pos-customer']!;
    expect(customerTemplate.pattern, '{qty} كرت {amount} {phone}');
    expect(customerTemplate.isActive, isTrue);
  });

  test('repairs and reactivates an existing legacy customer-delivery default', () async {
    final repo = _MemTemplates();
    repo.map['tpl-pos-pos-1-cards-to-pos-customer'] = TransferTemplate(
      id: 'tpl-pos-pos-1-cards-to-pos-customer',
      name: 'قديماً',
      pattern: '{qty} كرت {amount} {dest}',
      isActive: false,
      posId: 'pos-1',
      requireReference: false,
    );

    await DefaultPosTemplatesSeeder(templates: repo).seedForPos(
      posId: 'pos-1',
      posName: 'نقطة',
    );

    final repaired = repo.map['tpl-pos-pos-1-cards-to-pos-customer']!;
    expect(repaired.pattern, '{qty} كرت {amount} {phone}');
    expect(repaired.name, 'إرسال كروت إلى عميل نقطة البيع');
    expect(repaired.sampleBody, '1 كرت 100 779776919');
    expect(repaired.isActive, isTrue);
  });

  test('deactivates retired default variants without deleting custom templates', () async {
    final repo = _MemTemplates();
    repo.map['tpl-pos-pos-1-normal'] = TransferTemplate(
      id: 'tpl-pos-pos-1-normal',
      name: 'طلب كرت لعميل',
      pattern: '{phone} {amount}',
      isActive: true,
      posId: 'pos-1',
      requireReference: false,
    );
    repo.map['custom-pos-1'] = TransferTemplate(
      id: 'custom-pos-1',
      name: 'قالب مخصص',
      pattern: 'رصيدي',
      isActive: true,
      posId: 'pos-1',
      requireReference: false,
    );
    await DefaultPosTemplatesSeeder(templates: repo).seedForPos(
      posId: 'pos-1',
      posName: 'نقطة',
    );
    expect(repo.map['tpl-pos-pos-1-normal']!.isActive, isFalse);
    expect(repo.map['custom-pos-1']!.isActive, isTrue);
    expect(repo.map['tpl-pos-pos-1-cards-to-pos']!.isActive, isTrue);
  });

  test('customer template requires quantity, category, then customer phone', () async {
    final repo = _MemTemplates();
    await DefaultPosTemplatesSeeder(templates: repo).seedForPos(
      posId: 'pos-1',
      posName: 'نقطة',
    );
    final parser = LocalMessageParser(templates: repo.map.values.toList());

    final single = parser.parse(
      IncomingMessage(
        id: 'customer-1',
        sender: '779000111',
        body: '1 كرت 100 779776919',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(single, isA<Success<ParsedTransfer>>());
    final singleValue = (single as Success<ParsedTransfer>).value;
    expect(singleValue.quantity, 1);
    expect(singleValue.amount.minorUnits, 10000);
    expect(singleValue.customerIdentifier, '779000111');
    expect(singleValue.deliveryOverride, '779776919');
    expect(singleValue.posId, 'pos-1');

    final batch = parser.parse(
      IncomingMessage(
        id: 'customer-2',
        sender: '779000111',
        body: '3 كروت 100 779776919',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(batch, isA<Success<ParsedTransfer>>());
    final batchValue = (batch as Success<ParsedTransfer>).value;
    expect(batchValue.quantity, 3);
    expect(batchValue.amount.minorUnits, 10000);
    expect(batchValue.customerIdentifier, '779000111');
    expect(batchValue.deliveryOverride, '779776919');

    final oldOrder = parser.parse(
      IncomingMessage(
        id: 'customer-old',
        sender: '779000111',
        body: '779776919 100 3',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(oldOrder, isA<Failure<ParsedTransfer>>());
  });

  test('parses Arabic POS stock phrase and keeps POS identity separate from delivery', () async {
    final repo = _MemTemplates();
    await DefaultPosTemplatesSeeder(templates: repo).seedForPos(
      posId: 'pos-1',
      posName: 'نقطة',
    );
    final parser = LocalMessageParser(templates: repo.map.values.toList());

    final toPos = parser.parse(
      IncomingMessage(
        id: 'm1',
        sender: '779000111',
        body: '10 كروت 100',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(toPos, isA<Success<ParsedTransfer>>());
    final stock = (toPos as Success<ParsedTransfer>).value;
    expect(stock.quantity, 10);
    expect(stock.amount.minorUnits, 10000);
    expect(stock.customerIdentifier, '779000111');
    expect(stock.deliveryOverride, '779000111');

    final toCustomer = parser.parse(
      IncomingMessage(
        id: 'm2',
        sender: '779000111',
        body: '777123456 100 2',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(toCustomer, isA<Success<ParsedTransfer>>());
    final dest = (toCustomer as Success<ParsedTransfer>).value;
    expect(dest.quantity, 2);
    expect(dest.customerIdentifier, '779000111');
    expect(dest.deliveryOverride, '777123456');
  });

  test('custom POS template still supports explicit Arabic destination syntax', () {
    final parser = LocalMessageParser(
      templates: [
        TransferTemplate(
          id: 'custom-pos-dest',
          name: 'قالب مخصص',
          pattern: '{qty} كرت {amount} {dest}',
          isActive: true,
          posId: 'pos-1',
          requireReference: false,
        ),
      ],
    );

    final parsed = parser.parse(
      IncomingMessage(
        id: 'm3',
        sender: '779000111',
        body: '1 كرت 100 777123456',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.quantity, 1);
    expect(value.customerIdentifier, '779000111');
    expect(value.deliveryOverride, '777123456');
  });
}
