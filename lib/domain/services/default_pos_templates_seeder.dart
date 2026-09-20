import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Seeds the 5 built-in parse templates for a single point-of-sale as part of
/// the centralized POS profile creation transaction. The seeding is keyed by
/// `posId`, so each POS gets its own copy and repeated calls are idempotent.
///
/// Unlike [DefaultWalletTemplatesSeeder] (global, gated by a settings
/// flag), this seeder has a POS-specific key and is owned by the profile
/// lifecycle service.
////// idempotent per POS (stable ids `tpl-pos-{posId}-{variant}`, upsert),
/// so calling it again for the same POS is harmless.
///
/// Fidelity note: the 5th template ("قالب طلب رصيد نقطة البيع") mirrors
/// the video visually (name/priority/sample "111") but is not yet
/// functionally wired — [LocalMessageParser] always requires a captured
/// `{amount}`, and a bare balance-request code has none. Making it truly
/// functional needs a small dedicated "balance query" path (matching the
/// literal code against the body and resolving the identifier from
/// `message.sender` instead of the body) plus a service that replies with
/// the POS balance — deliberately left as follow-up work rather than
/// bolted on here.
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
      pattern: '{amount}',
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
