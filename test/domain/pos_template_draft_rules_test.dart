import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/default_pos_templates_seeder.dart';
import 'package:net_app/domain/template_draft_rules.dart';

import '../helpers/in_memory_repositories.dart';

void main() {
  group('isTemplateDraft', () {
    test('POS cards template reads identity from sender — not a draft', () {
      const template = TransferTemplate(
        id: 'tpl-pos-pos-1-cards-to-pos',
        name: 'إرسال كروت إلى نقطة البيع',
        pattern: '{qty} كرت {amount}',
        isActive: false,
        posId: 'pos-1',
        identifierKind: TemplateIdentifierKind.senderNameOnly,
        requireReference: false,
      );

      expect(isTemplateDraft(template), isFalse);
    });

    test('balance request template is never a draft', () {
      const template = TransferTemplate(
        id: 'tpl-pos-pos-1-balance-request',
        name: 'استعلام رصيد نقطة البيع',
        pattern: '111',
        isActive: true,
        posId: 'pos-1',
        identifierKind: TemplateIdentifierKind.balanceRequestCode,
        requireReference: false,
      );

      expect(isTemplateDraft(template), isFalse);
    });

    test('phone template without a phone placeholder is a draft', () {
      const template = TransferTemplate(
        id: 'legacy',
        name: 'قديم',
        pattern: '{qty} كرت {amount}',
        isActive: true,
        identifierKind: TemplateIdentifierKind.phone,
      );

      expect(isTemplateDraft(template), isTrue);
    });

    test('template without amount is a draft', () {
      const template = TransferTemplate(
        id: 'no-amount',
        name: 'بلا مبلغ',
        pattern: 'ارسل {qty} كرت',
        isActive: true,
        identifierKind: TemplateIdentifierKind.senderNameOnly,
      );

      expect(isTemplateDraft(template), isTrue);
    });
  });

  group('DefaultPosTemplatesSeeder draft safety', () {
    test('every seeded POS template is activatable (none is a draft)', () async {
      final repo = InMemoryTransferTemplateRepository();
      final seeded = await DefaultPosTemplatesSeeder(templates: repo)
          .seedForPos(posId: 'pos-1', posName: 'نقطة');

      expect(seeded, isA<Success<int>>());
      final all =
          (await repo.listAll() as Success<List<TransferTemplate>>).value;
      expect(all, hasLength(DefaultPosTemplatesSeeder.catalogSize));
      for (final template in all) {
        expect(
          isTemplateDraft(template),
          isFalse,
          reason: '${template.name} يجب أن يكون قابلًا للتفعيل',
        );
      }
    });

    test('repairs the legacy cards-to-pos row to sender identity', () async {
      final repo = InMemoryTransferTemplateRepository();
      await repo.save(
        const TransferTemplate(
          id: 'tpl-pos-pos-1-cards-to-pos',
          name: 'إرسال كروت إلى نقطة البيع',
          pattern: '{qty} كرت {amount}',
          isActive: false,
          posId: 'pos-1',
          requireReference: false,
        ),
      );

      await DefaultPosTemplatesSeeder(templates: repo)
          .seedForPos(posId: 'pos-1', posName: 'نقطة');

      final repaired = (await repo.findById('tpl-pos-pos-1-cards-to-pos')
              as Success<TransferTemplate?>)
          .value!;
      expect(repaired.identifierKind, TemplateIdentifierKind.senderNameOnly);
      expect(isTemplateDraft(repaired), isFalse);
      expect(repaired.isActive, isTrue);
    });

    test('never rewrites an operator-customised POS pattern', () async {
      final repo = InMemoryTransferTemplateRepository();
      await repo.save(
        const TransferTemplate(
          id: 'tpl-pos-pos-1-cards-to-pos',
          name: 'قالب المشغّل',
          pattern: 'ارسل {qty} كرت {amount}',
          isActive: false,
          posId: 'pos-1',
          requireReference: false,
        ),
      );

      await DefaultPosTemplatesSeeder(templates: repo)
          .seedForPos(posId: 'pos-1', posName: 'نقطة');

      final kept = (await repo.findById('tpl-pos-pos-1-cards-to-pos')
              as Success<TransferTemplate?>)
          .value!;
      expect(kept.name, 'قالب المشغّل');
      expect(kept.pattern, 'ارسل {qty} كرت {amount}');
      expect(kept.identifierKind, TemplateIdentifierKind.phone);
    });
  });
}
