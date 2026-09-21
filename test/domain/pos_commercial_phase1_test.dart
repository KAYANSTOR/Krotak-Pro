import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/domain.dart';
import 'package:net_app/domain/services/default_pos_templates_seeder.dart';
import 'package:net_app/domain/services/card_import_file_reader.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../helpers/in_memory_repositories.dart';

void main() {
  group('DefaultPosTemplatesSeeder commercial catalog', () {
    test('catalog size is exactly 3', () {
      expect(DefaultPosTemplatesSeeder.catalogSize, 3);
    });

    test('seedForPos inserts three active templates', () async {
      final repo = InMemoryTransferTemplateRepository();
      final seeder = DefaultPosTemplatesSeeder(templates: repo);
      final r = await seeder.seedForPos(posId: 'pos-1', posName: 'اختبار');
      expect(r, isA<Success<int>>());
      final list = (await repo.listAll() as Success<List<TransferTemplate>>).value
          .where((t) => t.posId == 'pos-1' && t.isActive)
          .toList();
      expect(list.length, 3);
      final names = list.map((e) => e.name).toSet();
      expect(names, contains('إرسال كروت إلى نقطة البيع'));
      expect(names, contains('إرسال كروت إلى عميل نقطة البيع'));
      expect(names, contains('استعلام رصيد نقطة البيع'));
    });

    test('seedForPos is add-missing-only', () async {
      final repo = InMemoryTransferTemplateRepository();
      final seeder = DefaultPosTemplatesSeeder(templates: repo);
      await seeder.seedForPos(posId: 'pos-1', posName: 'أ');
      final first = (await repo.listAll() as Success<List<TransferTemplate>>).value.length;
      final r2 = await seeder.seedForPos(posId: 'pos-1', posName: 'أ');
      expect((r2 as Success<int>).value, 0);
      final second = (await repo.listAll() as Success<List<TransferTemplate>>).value.length;
      expect(second, first);
    });
  });

  group('CardImportFileReader commercial types', () {
    test('rejects txt extension', () {
      final r = CardImportFileReader.read(
        fileName: 'cards.txt',
        bytes: Uint8List.fromList(utf8.encode('10001,secret')),
      );
      expect(r.kind, CardImportFileKind.unsupported);
    });

    test('accepts csv with content', () {
      final r = CardImportFileReader.read(
        fileName: 'cards.csv',
        bytes: Uint8List.fromList(utf8.encode('10001,abcd\n10002,efgh')),
      );
      expect(r.kind, CardImportFileKind.csv);
      expect(r.isOk, isTrue);
    });

    test('rejects png magic with csv extension', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
      final r = CardImportFileReader.read(fileName: 'fake.csv', bytes: png);
      expect(r.kind, CardImportFileKind.unsupported);
    });

    test('rejects non-pdf magic with pdf extension', () {
      final r = CardImportFileReader.read(
        fileName: 'x.pdf',
        bytes: Uint8List.fromList(utf8.encode('not a pdf')),
      );
      expect(r.kind, CardImportFileKind.unsupported);
    });

    test('allowedExtensions are pdf xlsx csv only', () {
      expect(CardImportFileReader.allowedExtensions.toSet(), {'pdf', 'xlsx', 'csv'});
    });
  });
}

