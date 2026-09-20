import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/local_message_parser.dart';

IncomingMessage _msg(String body, {String sender = '777000111'}) {
  return IncomingMessage(
    id: 'm1',
    sender: sender,
    body: body,
    receivedAt: DateTime.utc(2026, 9, 20),
    status: MessageProcessingStatus.received,
  );
}

void main() {
  final posTemplate = TransferTemplate(
    id: 'tpl-pos-1-normal',
    name: 'قالب نقطة البيع',
    pattern: '{phone} {amount}',
    isActive: true,
    posId: 'pos-1',
    requireReference: false,
  );

  final reversed = TransferTemplate(
    id: 'tpl-pos-1-reversed',
    name: 'قالب نقطة البيع (معكوس)',
    pattern: '{amount} {phone}',
    isActive: true,
    posId: 'pos-1',
    requireReference: false,
    priority: 1,
  );

  test('keyword شحن bills sender and delivers to body phone', () {
    final parser = LocalMessageParser(templates: [posTemplate]);
    final parsed = parser.parse(_msg('شحن 779776919 100', sender: '777000111'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.instantCharge, isTrue);
    expect(value.customerIdentifier, '777000111');
    expect(value.deliveryOverride, '779776919');
    expect(value.amount.minorUnits, 10000);
    expect(value.quantity, 1);
  });

  test('arabic phrase send card amount to phone', () {
    final parser = LocalMessageParser(templates: [posTemplate, reversed]);
    final parsed = parser.parse(
      _msg('ارسل كرت 50 الى 733123456', sender: '711111111'),
    );
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.instantCharge, isTrue);
    expect(value.customerIdentifier, '711111111');
    expect(value.deliveryOverride, '733123456');
    expect(value.amount.minorUnits, 5000);
  });

  test('explicit dest without keyword keeps ledger phone and overrides delivery', () {
    final parser = LocalMessageParser(
      templates: [
        TransferTemplate(
          id: 'tpl-dest',
          name: 'وجهة',
          pattern: '{phone} {amount} {dest}',
          isActive: true,
          posId: 'pos-1',
          requireReference: false,
        ),
      ],
    );
    final parsed = parser.parse(_msg('779776919 100 733123456'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.instantCharge, isFalse);
    expect(value.customerIdentifier, '779776919');
    expect(value.deliveryOverride, '733123456');
  });

  test('plain POS request is not instant charge', () {
    final parser = LocalMessageParser(templates: [posTemplate]);
    final parsed = parser.parse(_msg('779776919 100'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.instantCharge, isFalse);
    expect(value.deliveryOverride, isNull);
    expect(value.customerIdentifier, '779776919');
  });
}
