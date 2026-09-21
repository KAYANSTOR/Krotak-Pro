import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Seeds the built-in **inbound** parse templates for a single point-of-sale.
///
/// Catalog is exactly three default inbound types (Phase 43 §3):
/// 1. Send cards to the POS itself: `{qty} كرت {amount}`
/// 2. Send cards to a POS customer: `{qty} كرت {amount} {dest}`
/// 3. POS balance inquiry: `111`
///
/// POS identity is never part of the pattern — it comes from the sender.
/// [overwriteExisting] = false is add-missing-only and never re-activates a
/// template the operator already turned off.
final class DefaultPosTemplatesSeeder {
  const DefaultPosTemplatesSeeder({required this.templates});

  final TransferTemplateRepository templates;

  /// Number of built-in variants currently defined (for tests / UI hints).
  static int get catalogSize => _specs.length;

  static const retiredDefaultVariants = <String>{
    'multi-qty-dest',
    'multi-qty-dest-reversed',
    'multi-qty',
    'multi-qty-reversed',
    'dest',
    'dest-reversed',
    'normal',
    'reversed',
    'arabic-digits',
    'arabic-digits-reversed',
  };

  Future<Result<int>> seedForPos({
    required String posId,
    required String posName,
    bool overwriteExisting = false,
  }) async {
    final existingResult = await templates.listAll();
    if (existingResult is Failure<List<TransferTemplate>>) {
      return Failure(existingResult.error);
    }
    final existing = (existingResult as Success<List<TransferTemplate>>).value;
    final byId = {for (final t in existing) t.id: t};

    var inserted = 0;
    for (final spec in _specs) {
      final id = 'tpl-pos-$posId-${spec.variant}';
      final current = byId[id];
      if (current != null && !overwriteExisting) continue;
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

    for (final variant in retiredDefaultVariants) {
      final id = 'tpl-pos-$posId-$variant';
      final current = byId[id];
      if (current == null || !current.isActive) continue;
      final saved = await templates.save(current.copyWith(isActive: false));
      if (saved is Failure<void>) return Failure(saved.error);
    }
    return Success(inserted);
  }

  static const _specs = <_TplSpec>[
    _TplSpec(
      variant: 'deliver-to-customer',
      name: 'إرسال كروت إلى عميل نقطة البيع',
      priority: 1,
      pattern: '{qty} كرت {amount} {dest}',
      sampleBody: '3 كروت 200 771234567',
      senderNameLabel: 'غير معروف',
      noteLabel: 'إرسال كروت لعميل النقطة',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'stock-to-pos',
      name: 'إرسال كروت إلى نقطة البيع',
      priority: 2,
      pattern: '{qty} كرت {amount}',
      sampleBody: '10 كروت 100',
      senderNameLabel: 'غير معروف',
      noteLabel: 'إرسال كروت للنقطة',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'balance-request',
      name: 'استعلام رصيد نقطة البيع',
      priority: 20,
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
  final bool requireReference;
}
