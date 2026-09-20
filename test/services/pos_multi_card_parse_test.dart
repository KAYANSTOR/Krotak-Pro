import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/local_message_parser.dart';

IncomingMessage _msg(String body) {
  return IncomingMessage(
    id: 'm1',
    sender: '777000111',
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

  final walletTemplate = TransferTemplate(
    id: 'tpl-wallet',
    name: 'محفظة',
    pattern: 'حولت {amount} الى {phone} رقم العملية {ref}',
    isActive: true,
  );

  test('POS message without qty stays quantity 1', () {
    final parser = LocalMessageParser(templates: [posTemplate]);
    final parsed = parser.parse(_msg('779776919 100'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.quantity, 1);
    expect(value.amount.minorUnits, 10000);
    expect(value.customerIdentifier, '779776919');
    expect(value.posId, 'pos-1');
  });

  test('POS message with trailing qty parses batch size', () {
    final parser = LocalMessageParser(templates: [posTemplate]);
    final parsed = parser.parse(_msg('779776919 100 3'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.quantity, 3);
    expect(value.amount.minorUnits, 10000);
  });

  test('explicit {qty} placeholder works', () {
    final parser = LocalMessageParser(
      templates: [
        TransferTemplate(
          id: 'tpl-qty',
          name: 'كمية',
          pattern: '{phone} {amount} {qty}',
          isActive: true,
          posId: 'pos-1',
          requireReference: false,
        ),
      ],
    );
    final parsed = parser.parse(_msg('779776919 50 2'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    expect((parsed as Success<ParsedTransfer>).value.quantity, 2);
  });

  test('qty above 20 is rejected', () {
    final parser = LocalMessageParser(templates: [posTemplate]);
    final parsed = parser.parse(_msg('779776919 100 21'));
    expect(parsed, isA<Failure<ParsedTransfer>>());
  });

  test('POS instant charge extracts sender ledger and destination', () {
    final parser = LocalMessageParser(templates: [posTemplate]);
    final parsed = parser.parse(_msg('شحن 779776919 100'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.instantCharge, isTrue);
    expect(value.customerIdentifier, '777000111');
    expect(value.deliveryOverride, '779776919');
    expect(value.amount.minorUnits, 10000);
  });

  test('POS Arabic instant charge phrase extracts destination', () {
    final parser = LocalMessageParser(templates: [posTemplate]);
    final parsed = parser.parse(_msg('ارسل كرت 50 الى 733123456'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.instantCharge, isTrue);
    expect(value.customerIdentifier, '777000111');
    expect(value.deliveryOverride, '733123456');
    expect(value.amount.minorUnits, 5000);
  });

  test('wallet leftover digits are not treated as qty', () {
    final parser = LocalMessageParser(templates: [walletTemplate]);
    final parsed = parser.parse(
      _msg('حولت 100 الى 779776919 رقم العملية ABC99 4'),
    );
    expect(parsed, isA<Failure<ParsedTransfer>>());
  });

  test('custom POS balance template is parsed as a balance request', () {
    final parser = LocalMessageParser(
      templates: [
        TransferTemplate(
          id: 'tpl-pos-custom-balance',
          name: 'رصيدي',
          pattern: 'رصيدي',
          isActive: true,
          posId: 'pos-1',
          identifierKind: TemplateIdentifierKind.balanceRequestCode,
          requireReference: false,
        ),
      ],
    );
    final parsed = parser.parse(_msg('رصيدي'));
    expect(parsed, isA<Success<ParsedTransfer>>());
    final value = (parsed as Success<ParsedTransfer>).value;
    expect(value.amount.minorUnits, 0);
    expect(value.reference, startsWith('balance-request:'));
  });
}
