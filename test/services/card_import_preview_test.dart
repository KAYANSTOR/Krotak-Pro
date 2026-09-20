import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/services/card_import_file_reader.dart';
import 'package:net_app/domain/services/card_import_parser.dart';
import 'package:net_app/domain/services/services.dart';

import '../helpers/in_memory_repositories.dart';

void main() {
  late InMemoryCardRepository cards;

  setUp(() {
    cards = InMemoryCardRepository();
  });

  test('preview flags serials already in stock', () async {
    await cards.save(
      const Card(
        id: 'c1',
        categoryId: 'cat-1',
        serialNumber: 'DUP',
        secretCode: 'X',
        status: CardStatus.available,
      ),
    );
    final parsed = CardImportParser.parse('DUP,AAA\nNEW,BBB');
    final existing = await cards.existingSerialsAmong(
      parsed.drafts.map((d) => d.serialNumber),
    );
    final value = CardImportPreview(
      drafts: parsed.drafts,
      parseErrors: parsed.errors,
      stockDuplicateSerials: (existing as Success<Set<String>>).value,
      fileName: 'cards.csv',
    );
    expect(value.stockDuplicateSerials, contains('DUP'));
    expect(value.acceptedDrafts.single.serialNumber, 'NEW');
    expect(value.canImport, isTrue);
    expect(value.fileName, 'cards.csv');
  });

  test('csv reader strips bom and keeps lines', () {
    final bom = Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('A,B\nC,D\n')]);
    final r = CardImportFileReader.read(fileName: 'stock.csv', bytes: bom);
    expect(r.kind, CardImportFileKind.csv);
    final parsed = CardImportParser.parse(r.text);
    expect(parsed.drafts.map((d) => d.serialNumber), ['A', 'C']);
  });

  test('pdf reader extracts Tj literals', () {
    final pdf = utf8.encode(
      '%PDF-1.4\n1 0 obj\n<<>>\nstream\nBT (10001) Tj (PINA) Tj ET\nendstream',
    );
    final r = CardImportFileReader.read(
      fileName: 'cards.pdf',
      bytes: Uint8List.fromList(pdf),
    );
    expect(r.kind, CardImportFileKind.pdf);
    expect(r.text, contains('10001'));
    expect(r.text, contains('PINA'));
  });
}
