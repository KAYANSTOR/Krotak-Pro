import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/services/card_import_file_reader.dart';
import 'package:net_app/domain/services/card_import_parser.dart';
import 'package:net_app/domain/services/card_import_preview.dart';
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

  test('rejects txt extension', () {
    final r = CardImportFileReader.read(
      fileName: 'cards.txt',
      bytes: Uint8List.fromList(utf8.encode('A,B\n')),
    );
    expect(r.kind, CardImportFileKind.unsupported);
    expect(r.errorCode, 'unsupported_file_type');
  });

  test('rejects png image even when renamed csv', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
    final r = CardImportFileReader.read(fileName: 'cards.csv', bytes: png);
    expect(r.kind, CardImportFileKind.unsupported);
    expect(r.errorCode, 'unsupported_file_type');
  });

  test('rejects jpeg image even when renamed csv', () {
    final jpg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0, 1, 2, 3]);
    final r = CardImportFileReader.read(fileName: 'stock.csv', bytes: jpg);
    expect(r.kind, CardImportFileKind.unsupported);
  });

  test('rejects pdf magic masquerading as csv', () {
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4\nBT (X) Tj ET'));
    final r = CardImportFileReader.read(fileName: 'cards.csv', bytes: pdf);
    expect(r.kind, CardImportFileKind.unsupported);
  });

  test('rejects zip/xlsx magic masquerading as csv', () {
    final zip = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 0, 1, 2, 3]);
    final r = CardImportFileReader.read(fileName: 'cards.csv', bytes: zip);
    expect(r.kind, CardImportFileKind.unsupported);
  });

  test('rejects pdf extension without pdf magic (spoofed)', () {
    final r = CardImportFileReader.read(
      fileName: 'cards.pdf',
      bytes: Uint8List.fromList(utf8.encode('not a pdf')),
    );
    expect(r.kind, CardImportFileKind.unsupported);
  });

  test('rejects xlsx extension without zip magic (spoofed)', () {
    final r = CardImportFileReader.read(
      fileName: 'cards.xlsx',
      bytes: Uint8List.fromList(utf8.encode('not zip')),
    );
    expect(r.kind, CardImportFileKind.unsupported);
  });
}
