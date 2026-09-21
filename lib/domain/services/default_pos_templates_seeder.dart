import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Seeds the built-in **inbound** parse templates for a single point-of-sale.
///
/// Commercial catalog (Krotak Pro full-completion plan §3): **exactly three**
/// default inbound POS templates. POS identity is always taken from the SMS
/// sender / registered identifier — never from the message body.
///
/// 1. Cards to the POS itself: `{qty} كرت {amount}`
/// 2. Cards to a POS customer: `{qty} كرت {amount} {dest}`
/// 3. Balance inquiry: `111`
///
/// Custom templates the operator creates are left untouched. Seeding is
/// **add-missing-only** unless [overwriteExisting] is true.
final class DefaultPosTemplatesSeeder {
  const DefaultPosTemplatesSeeder({required this.templates});

  final TransferTemplateRepository templates;

  /// Number of built-in variants (always 3 for the commercial catalog).
  static int get catalogSize => _specs.length;

  /// Legacy default variant ids that are no longer part of the commercial
  /// catalog. Existing rows are **deactivated** (not deleted) so custom text
  /// is preserved and audit history stays intact.
  static const legacyDefaultVariants = <String>{
    'multi',
    'multi-reversed',
    'multi-dest',
    'multi-dest-reversed',
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
    final existing = await templates.listAll();
    if (existing is Failure<List<TransferTemplate>>) {
      return Failure(existing.error);
    }
    final all = (existing as Success<List<TransferTemplate>>).value;
    final byId = {for (final t in all) t.id: t};
    final existingIds = !overwriteExisting
        ? byId.keys.toSet()
        : const <String>{};

    var changed = 0;

    // Deactivate legacy default variants for this POS (add-missing / migrate).
    for (final t in all) {
      if (!t.id.startsWith('tpl-pos-$posId-')) continue;
      final variant = t.id.substring('tpl-pos-$posId-'.length);
      if (!legacyDefaultVariants.contains(variant)) continue;
      if (!t.isActive) continue;
      final deactivated = TransferTemplate(
        id: t.id,
        name: t.name,
        pattern: t.pattern,
        isActive: false,
        priority: t.priority,
        walletId: t.walletId,
        posId: t.posId,
        sampleBody: t.sampleBody,
        identifierKind: t.identifierKind,
        senderNameLabel: t.senderNameLabel,
        noteLabel: t.noteLabel,
        requireReference: t.requireReference,
      );
      final save = await templates.save(deactivated);
      if (save is Failure<void>) return Failure(save.error);
      changed++;
    }

    for (final spec in _specs) {
      final id = 'tpl-pos-$posId-${spec.variant}';
      if (existingIds.contains(id)) {
        // Never re-enable or overwrite an existing built-in template here.
        // A disabled/customized template is an explicit operator decision.
        continue;
      }
      final tpl = TransferTemplate(
        id: id,
        name: spec.name,
        pattern: spec.pattern,
        isActive: true,
        priority: spec.priority,
        walletId: null,
        posId: posId,
        sampleBody: spec.sampleBody,
        identifierKind: spec.identifierKind,
        senderNameLabel: spec.senderNameLabel,
        noteLabel: spec.noteLabel,
        requireReference: spec.requireReference,
      );
      final save = await templates.save(tpl);
      if (save is Failure<void>) return Failure(save.error);
      changed++;
    }
    return Success(changed);
  }

  static const _specs = <_TplSpec>[
    // 1 — إرسال كروت إلى نقطة البيع (الهوية من المرسل)
    _TplSpec(
      variant: 'cards-to-pos',
      name: 'إرسال كروت إلى نقطة البيع',
      priority: 1,
      pattern: '{qty} كرت {amount}',
      sampleBody: '10 كرت 100',
      senderNameLabel: 'نقطة البيع',
      noteLabel: 'كروت لنقطة البيع',
      requireReference: false,
    ),
    // 2 — إرسال كروت إلى عميل نقطة البيع
    _TplSpec(
      variant: 'cards-to-pos-customer',
      name: 'إرسال كروت إلى عميل نقطة البيع',
      priority: 2,
      pattern: '{qty} كرت {amount} {dest}',
      sampleBody: '1 كرت 100 777123456',
      senderNameLabel: 'نقطة البيع',
      noteLabel: 'كروت لعميل نقطة البيع',
      requireReference: false,
    ),
    // 3 — استعلام رصيد نقطة البيع
    _TplSpec(
      variant: 'balance-request',
      name: 'استعلام رصيد نقطة البيع',
      priority: 20,
      pattern: '111',
      sampleBody: '111',
      identifierKind: TemplateIdentifierKind.balanceRequestCode,
      senderNameLabel: 'نقطة البيع',
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
