import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';

/// Seeds built-in parse templates for the four default Yemen wallets.
///
/// Patterns follow the product video samples so JAIB / JAWALI /
/// ONE CASH / FLOOSAK work without manual wizard setup. New wallets still
/// require operator-defined templates.
final class DefaultWalletTemplatesSeeder {
  const DefaultWalletTemplatesSeeder({
    required this.wallets,
    required this.templates,
    required this.settings,
    required this.clock,
    required this.ids,
  });

  final WalletRepository wallets;
  final TransferTemplateRepository templates;
  final SettingsRepository settings;
  final Clock clock;
  final IdGenerator ids;

  static const seededKey = 'default_wallet_templates_seeded_v2';

  /// Idempotent: skips when [seededKey] is set, otherwise inserts missing
  /// templates keyed by stable id `tpl-default-{senderId}-{variant}`.
  Future<Result<int>> seedIfNeeded() async {
    final flag = await settings.find(seededKey);
    if (flag is Success<AppSetting?> && flag.value?.value == 'true') {
      return const Success(0);
    }

    final walletList = await wallets.listAll();
    if (walletList is Failure<List<Wallet>>) {
      return Failure(walletList.error);
    }
    final bySender = <String, Wallet>{};
    for (final w in (walletList as Success<List<Wallet>>).value) {
      final sid = (w.senderId ?? '').trim().toUpperCase();
      if (sid.isNotEmpty) bySender[sid] = w;
      final name = w.name.trim();
      if (name == 'جيب') bySender.putIfAbsent('JAIB', () => w);
      if (name == 'جوالي') bySender.putIfAbsent('JAWALI', () => w);
      if (name == 'ون كاش') bySender.putIfAbsent('ONE CASH', () => w);
      if (name == 'فلوسك') bySender.putIfAbsent('FLOOSAK', () => w);
    }

    final existing = await templates.listAll();
    if (existing is Failure<List<TransferTemplate>>) {
      return Failure(existing.error);
    }
    final byId = {
      for (final t in (existing as Success<List<TransferTemplate>>).value) t.id: t,
    };

    var inserted = 0;
    for (final spec in _specs) {
      final wallet = bySender[spec.senderCode.toUpperCase()];
      final id =
          'tpl-default-${spec.senderCode.toLowerCase().replaceAll(' ', '-')}-${spec.variant}';
      if (byId.containsKey(id)) continue;

      final tpl = TransferTemplate(
        id: id,
        name: spec.name,
        pattern: spec.pattern,
        isActive: true,
        walletId: wallet?.id,
        priority: spec.priority,
        sampleBody: spec.sampleBody,
        senderCode: spec.senderCode,
        identifierKind: TemplateIdentifierKind.phone,
      );
      final saved = await templates.save(tpl);
      if (saved is Failure<void>) return Failure(saved.error);
      inserted += 1;
    }

    await settings.save(
      AppSetting(key: seededKey, value: 'true', updatedAt: clock.now()),
    );
    return Success(inserted);
  }

  static const _specs = <_TplSpec>[
    _TplSpec(
      senderCode: 'JAIB',
      variant: 'ar-shared',
      name: 'جيب — تحويل مشترك',
      priority: 10,
      pattern:
          'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}',
      sampleBody:
          'اضيف 5000 ر.ي تحويل مشترك رص:5500.36 ر.ي من وليد العمري-770455491',
    ),
    _TplSpec(
      senderCode: 'JAIB',
      variant: 'ar-phone-only',
      name: 'جيب — تحويل (رقم فقط)',
      priority: 20,
      pattern: 'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {phone}',
      sampleBody: 'اضيف 10 ر.ي تحويل مشترك رص:1022 ر.ي من 687471',
    ),
    _TplSpec(
      senderCode: 'JAIB',
      variant: 'en-received',
      name: 'JAIB — received (EN)',
      priority: 30,
      pattern: 'You have received {amount} YER from {phone} your balance {ref}',
      sampleBody: 'You have received 10 YER from 779776919 your balance 20',
    ),
    _TplSpec(
      senderCode: 'JAWALI',
      variant: 'ar-shared',
      name: 'جوالي — تحويل مشترك',
      priority: 10,
      pattern:
          'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}',
      sampleBody:
          'اضيف 650 ر.ي تحويل مشترك رص:650 ر.ي من غير معروف-773303455',
    ),
    _TplSpec(
      senderCode: 'JAWALI',
      variant: 'ar-phone-only',
      name: 'جوالي — تحويل (رقم فقط)',
      priority: 20,
      pattern: 'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {phone}',
      sampleBody: 'اضيف 650 ر.ي تحويل مشترك رص:650 ر.ي من 773303455',
    ),
    _TplSpec(
      senderCode: 'JAWALI',
      variant: 'en-received',
      name: 'JAWALI — received (EN)',
      priority: 30,
      pattern: 'You have received {amount} YER from {phone} your balance {ref}',
      sampleBody: 'You have received 50 YER from 773303455 your balance 100',
    ),
    _TplSpec(
      senderCode: 'ONE CASH',
      variant: 'ar-shared',
      name: 'ون كاش — تحويل مشترك',
      priority: 10,
      pattern:
          'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}',
      sampleBody:
          'اضيف 1000 ر.ي تحويل مشترك رص:1000 ر.ي من عميل-771234567',
    ),
    _TplSpec(
      senderCode: 'ONE CASH',
      variant: 'ar-hawala',
      name: 'ون كاش — استلمت حوالة',
      priority: 15,
      pattern: 'استلمت حوالة من {account} بمبلغ {amount} ر.ي رصيدك {ref} ر.ي',
      sampleBody: 'استلمت حوالة من عميل بمبلغ 500.00 ر.ي رصيدك 1500.00 ر.ي',
    ),
    _TplSpec(
      senderCode: 'ONE CASH',
      variant: 'sms-generic',
      name: 'ون كاش — تحويل عام',
      priority: 20,
      pattern: 'تم استلام {amount} من {phone}',
      sampleBody: 'تم استلام 1000 من 771234567',
    ),
    _TplSpec(
      senderCode: 'FLOOSAK',
      variant: 'ar-shared',
      name: 'فلوسك — تحويل مشترك',
      priority: 10,
      pattern:
          'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}',
      sampleBody:
          'اضيف 2000 ر.ي تحويل مشترك رص:2000 ر.ي من عميل-770000001',
    ),
    _TplSpec(
      senderCode: 'FLOOSAK',
      variant: 'ar-hawala',
      name: 'فلوسك — استلمت حوالة',
      priority: 15,
      pattern: 'استلمت حوالة من {account} بمبلغ {amount} ر.ي رصيدك {ref} ر.ي',
      sampleBody: 'استلمت حوالة من محمد احمد بمبلغ 200.00 ر.ي رصيدك 600.00 ر.ي',
    ),
    _TplSpec(
      senderCode: 'FLOOSAK',
      variant: 'sms-generic',
      name: 'فلوسك — تحويل عام',
      priority: 20,
      pattern: 'تم استلام {amount} من {phone}',
      sampleBody: 'تم استلام 2000 من 770000001',
    ),
  ];
}

final class _TplSpec {
  const _TplSpec({
    required this.senderCode,
    required this.variant,
    required this.name,
    required this.priority,
    required this.pattern,
    required this.sampleBody,
  });

  final String senderCode;
  final String variant;
  final String name;
  final int priority;
  final String pattern;
  final String sampleBody;
}
