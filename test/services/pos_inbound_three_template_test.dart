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

  test('parses stock-to-POS and customer-delivery Arabic card phrases', () async {
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
    expect(stock.deliveryOverride, '779000111');

    final reversed = parser.parse(
      IncomingMessage(
        id: 'm1-reversed',
        sender: '779000111',
        body: '100 كرت 10',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(reversed, isA<Success<ParsedTransfer>>());
    final reversedValue = (reversed as Success<ParsedTransfer>).value;
    expect(reversedValue.quantity, 10);
    expect(reversedValue.amount.minorUnits, 10000);
    expect(reversedValue.customerIdentifier, '779000111');

    final arabicDigits = parser.parse(
      IncomingMessage(
        id: 'm1-ar',
        sender: '779000111',
        body: '١٠ كروت ١٠٠',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(arabicDigits, isA<Success<ParsedTransfer>>());

    final toCustomer = parser.parse(
      IncomingMessage(
        id: 'm2',
        sender: '779000111',
        body: '1 كرت 100 777123456',
        receivedAt: DateTime(2026, 9, 21),
        status: MessageProcessingStatus.received,
      ),
    );
    expect(toCustomer, isA<Success<ParsedTransfer>>());
    final dest = (toCustomer as Success<ParsedTransfer>).value;
    expect(dest.quantity, 1);
    expect(dest.deliveryOverride, '777123456');
  });
}
