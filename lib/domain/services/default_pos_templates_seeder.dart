import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Seeds the 5 built-in parse templates for a single point-of-sale, run
/// once right after a new POS point is created — mirrors the product
/// video: "نقطة بيع جديدة" → 5 قوالب تلقائية (نشط) تظهر مباشرة.
///
/// Unlike [DefaultWalletTemplatesSeeder] (global, gated by a settings
/// flag), this seeder is invoked directly by the UI at POS-creation time
/// and is keyed by `posId`, so each POS gets its own copy. It is
/// idempotent per POS (stable ids `tpl-pos-{posId}-{variant}`, upsert),
/// so calling it again for the same POS is harmless.
///
final class DefaultPosTemplatesSeeder {
  const DefaultPosTemplatesSeeder({required this.templates});

  final TransferTemplateRepository templates;

  Future<Result<int>> seedForPos({
    required String posId,
    required String posName,
  }) async {
    var inserted = 0;
    for (final spec in _specs) {
      final id = 'tpl-pos-$posId-${spec.variant}';
      final tpl = TransferTemplate(
        id: id,
        name: spec.name,
        pattern: spec.pattern,
        isActive: true,
        posId: posId,
        priority: spec.priority,
        sampleBody: spec.sampleBody,
        senderCode: posName,
        identifierKind: spec.identifierKind,
        senderNameLabel: spec.senderNameLabel,
        noteLabel: spec.noteLabel,
        requireReference: spec.requireReference,
      );
      final saved = await templates.save(tpl);
      if (saved is Failure<void>) return Failure(saved.error);
      inserted += 1;
    }
    return Success(inserted);
  }

  static const _specs = <_TplSpec>[
    _TplSpec(
      variant: 'normal',
      name: 'قالب نقطة البيع',
      priority: 0,
      pattern: '{phone} {amount}',
      sampleBody: '779776919 100',
      senderNameLabel: 'غير معروف',
      noteLabel: 'تحويل مشترك',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'reversed',
      name: 'قالب نقطة البيع (معكوس)',
      priority: 1,
      pattern: '{amount} {phone}',
      sampleBody: '100 779776919',
      senderNameLabel: 'غير معروف',
      noteLabel: 'تحويل مشترك',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'arabic-digits',
      name: 'قالب نقطة البيع (أرقام عربية)',
      priority: 2,
      pattern: '{phone} {amount}',
      sampleBody: '٧٧٩٧٧٦٩١٩ ١٠٠',
      senderNameLabel: 'غير معروف',
      noteLabel: 'تحويل مشترك',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'arabic-digits-reversed',
      name: 'قالب نقطة البيع (أرقام عربية معكوس)',
      priority: 3,
      pattern: '{amount} {phone}',
      sampleBody: '١٠٠ ٧٧٩٧٧٦٩١٩',
      senderNameLabel: 'غير معروف',
      noteLabel: 'تحويل مشترك',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'balance-request',
      name: 'قالب طلب رصيد نقطة البيع',
      priority: 4,
      pattern: '111',
      sampleBody: '111',
      identifierKind: TemplateIdentifierKind.balanceRequestCode,
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب رصيد',
      requireReference: false,
    ),
  ];
}

final class _TplSpec {
  const _TplSpec({
    required this.variant,
    required this.name,
    required this.priority,
    required this.pattern,
    required this.sampleBody,
    this.identifierKind = TemplateIdentifierKind.phone,
    this.senderNameLabel,
    this.noteLabel,
    this.requireReference = true,
  });

  final String variant;
  final String name;
  final int priority;
  final String pattern;
  final String sampleBody;
  final TemplateIdentifierKind identifierKind;
  final String? senderNameLabel;
  final String? noteLabel;

  /// These POS message formats carry no transaction reference at all —
  /// opt out of the parser's default "reference required" safety check.
  final bool requireReference;
}
