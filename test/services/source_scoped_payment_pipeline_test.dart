import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/local_message_parser.dart';

void main() {
  test('source-scoped parser selects only templates allowed for the source', () {
    final parser = LocalMessageParser(
      templates: const [
        TransferTemplate(
          id: 'wallet-a-template',
          name: 'Wallet A',
          pattern: 'PAY {amount} TO {phone} REF {ref}',
          isActive: true,
          walletId: 'wallet-a',
        ),
        TransferTemplate(
          id: 'wallet-b-template',
          name: 'Wallet B',
          pattern: 'PAY {amount} TO {phone} REF {ref}',
          isActive: true,
          walletId: 'wallet-b',
        ),
      ],
    );
    final message = IncomingMessage(
      id: 'm1',
      sender: 'A',
      body: 'PAY 10 TO 770000001 REF R1',
      receivedAt: DateTime.utc(2026, 10, 1),
      status: MessageProcessingStatus.received,
    );
    final result = parser.parseForSource(
      message,
      templateIds: {'wallet-b-template'},
    );
    expect(result, isA<Success<ParsedTransfer>>());
    expect((result as Success<ParsedTransfer>).value.templateId, 'wallet-b-template');
  });
}
