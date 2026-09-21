import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Seeds the built-in **inbound** parse templates for a single point-of-sale.
///
/// Invoked by [LocalPosProfileService.create] right after a new POS is saved
/// so the operator sees a full working catalog immediately (product video:
/// «نقطة بيع جديدة» → قوالب نشطة تظهر مباشرة).
///
/// Unlike [DefaultWalletTemplatesSeeder] (global, gated by a settings flag),
/// this seeder is keyed by `posId` — each POS gets its own copy. Stable ids
/// `tpl-pos-{posId}-{variant}` make the operation idempotent: calling
/// [seedForPos] again backfills any missing variants without duplicating rows
/// and, by default, without touching the state or the text of existing rows.
///
/// All variants are seeded **active**: one POS needs several patterns at once
/// (single card, multi card, delivery destination, balance request) and
/// [LocalMessageParser] picks the best match by ascending `priority`.
///
/// Catalog covers single-card, multi-card (`{qty}`), delivery override
/// (`{dest}`), and balance-request — matching what [LocalMessageParser]
/// already understands.
final class DefaultPosTemplatesSeeder {
  const DefaultPosTemplatesSeeder({required this.templates});

  final TransferTemplateRepository templates;

  /// Number of built-in variants currently defined (for tests / UI hints).
  static int get catalogSize => _specs.length;

  /// يزرع كتالوج القوالب الكامل لنقطة بيع.
  ///
  /// [overwriteExisting] = false (الافتراضي) يجعل العملية **إضافة الناقص فقط**
  /// فلا يُعاد تفعيل قالب أوقفه المشغّل عند كل تعديل لنقطة البيع، ولا يضيع أي
  /// تعديل يدوي على النص. فعّل [overwriteExisting] عند بناء/إصلاح الكتالوج.
  Future<Result<int>> seedForPos({
    required String posId,
    required String posName,
    bool overwriteExisting = false,
  }) async {
    final existing = await templates.listAll();
    if (existing is Failure<List<TransferTemplate>>) {
      return Failure(existing.error);
    }
    final existingIds = !overwriteExisting
        ? {
            for (final t in (existing as Success<List<TransferTemplate>>).value)
              t.id,
          }
        : const <String>{};
    var inserted = 0;
    for (final spec in _specs) {
      final id = 'tpl-pos-$posId-${spec.variant}';
      if (existingIds.contains(id)) continue;
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

  /// Full default inbound catalog.
  ///
  /// Priority is ascending in the parser (lower runs first). More-specific
  /// patterns (`{qty}`, `{dest}`) therefore use lower numbers so they win
  /// over the generic single-card patterns.
  static const _specs = <_TplSpec>[
    // ── multi-card + optional delivery destination (most specific) ──
    _TplSpec(
      variant: 'multi-qty-dest',
      name: 'طلب عدة كروت مع رقم التسليم',
      priority: 0,
      pattern: '{phone} {amount} {qty} {dest}',
      sampleBody: '779776919 100 3 733000111',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كروت متعدد + تسليم',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'multi-qty-dest-reversed',
      name: 'طلب عدة كروت مع رقم التسليم (معكوس)',
      priority: 1,
      pattern: '{amount} {phone} {qty} {dest}',
      sampleBody: '100 779776919 3 733000111',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كروت متعدد + تسليم',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'multi-qty',
      name: 'طلب عدة كروت لعميل',
      priority: 2,
      pattern: '{phone} {amount} {qty}',
      sampleBody: '779776919 100 3',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كروت متعدد',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'multi-qty-reversed',
      name: 'طلب عدة كروت لعميل (معكوس)',
      priority: 3,
      pattern: '{amount} {phone} {qty}',
      sampleBody: '100 779776919 3',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كروت متعدد',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'dest',
      name: 'طلب كرت مع رقم التسليم',
      priority: 4,
      pattern: '{phone} {amount} {dest}',
      sampleBody: '779776919 100 733000111',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كرت + تسليم',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'dest-reversed',
      name: 'طلب كرت مع رقم التسليم (معكوس)',
      priority: 5,
      pattern: '{amount} {phone} {dest}',
      sampleBody: '100 779776919 733000111',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كرت + تسليم',
      requireReference: false,
    ),

    // ── single-card (generic) ──
    _TplSpec(
      variant: 'normal',
      name: 'طلب كرت لعميل',
      priority: 10,
      pattern: '{phone} {amount}',
      sampleBody: '779776919 100',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كرت',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'reversed',
      name: 'طلب كرت لعميل (معكوس)',
      priority: 11,
      pattern: '{amount} {phone}',
      sampleBody: '100 779776919',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كرت',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'arabic-digits',
      name: 'طلب كرت (أرقام عربية)',
      priority: 12,
      pattern: '{phone} {amount}',
      sampleBody: '٧٧٩٧٧٦٩١٩ ١٠٠',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كرت',
      requireReference: false,
    ),
    _TplSpec(
      variant: 'arabic-digits-reversed',
      name: 'طلب كرت (أرقام عربية معكوس)',
      priority: 13,
      pattern: '{amount} {phone}',
      sampleBody: '١٠٠ ٧٧٩٧٧٦٩١٩',
      senderNameLabel: 'غير معروف',
      noteLabel: 'طلب كرت',
      requireReference: false,
    ),

    // ── balance ──
    _TplSpec(
      variant: 'balance-request',
      name: 'طلب رصيد نقطة البيع',
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

  /// POS request formats carry no bank transaction reference — opt out of
  /// the parser's default «reference required» safety check.
  final bool requireReference;
}
