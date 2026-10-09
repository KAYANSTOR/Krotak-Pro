import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/wallet.dart';
import '../repositories/repositories.dart';
import 'default_wallet_specs.dart';

/// Seeds built-in parse templates for the six approved deposit wallets.
///
/// Patterns follow the owner-approved deposit samples so Jaib / Jawali /
/// MFloos / Floosak / KuraimiLMB / ONE Cash work without manual wizard setup.
/// New wallets still require operator-defined templates.
///
/// قيم `senderCode` هنا هي قيم `Sender ID` الرسمية المعتمدة من المالك، وتُستخدم
/// فقط لربط القالب بمحفظته وللتصنيف في الواجهة — أما اعتماد مصدر الرسالة
/// ماليًا فيمرّ عبر [PaymentSourceGuard] بمطابقة تامة لقيمة المحفظة.
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

  static const seededKey = 'default_wallet_templates_seeded_v4';

  // Legacy JAIB default before the provider changed the separator from `-` to
  // a space between the sender name and phone number.
  static const _legacyJaibSharedPattern =
      'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}';

  /// Idempotent: skips the **insert** pass when [seededKey] is set, otherwise
  /// inserts missing templates keyed by stable id `tpl-default-{senderCode}-{variant}`.
  ///
  /// A cheap **repair** pass always runs afterwards: any built-in template that
  /// carries a `senderCode` of a known wallet but no (or a stale) `walletId` is
  /// re-linked. Without this the parser finds a template whose wallet does not
  /// match the incoming sender, [PaymentSourceGuard] reports `no_source_template`
  /// and the wallet's transfers are rejected even though they look configured.
  Future<Result<int>> seedIfNeeded() async {
    final flag = await settings.find(seededKey);
    final alreadySeeded =
        flag is Success<AppSetting?> && flag.value?.value == 'true';

    final walletList = await wallets.listAll();
    if (walletList is Failure<List<Wallet>>) {
      return Failure(walletList.error);
    }
    final walletValues = (walletList as Success<List<Wallet>>).value;

    final byWalletKey = <String, Wallet>{};
    final bySender = <String, Wallet>{};
    for (final w in walletValues) {
      final sid = (w.senderId ?? '').trim();
      if (sid.isNotEmpty) bySender[sid.toUpperCase()] = w;
      final name = w.name.trim();
      for (final spec in DefaultWalletSpecs.all) {
        if (name != spec.name) continue;
        byWalletKey.putIfAbsent(spec.key, () => w);
        final official = (spec.senderId ?? '').trim();
        if (official.isNotEmpty) {
          bySender.putIfAbsent(official.toUpperCase(), () => w);
        }
      }
    }

    final existing = await templates.listAll();
    if (existing is Failure<List<TransferTemplate>>) {
      return Failure(existing.error);
    }
    final all = (existing as Success<List<TransferTemplate>>).value;
    final byId = {for (final t in all) t.id: t};
    final knownWalletIds = {
      for (final w in walletValues) w.id,
    };

    var changed = 0;
    if (!alreadySeeded) {
      for (final spec in _specs) {
        final wallet = byWalletKey[spec.walletKey];
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
        changed += 1;
      }
    }

    // إصلاح الربط: قالب بمرسل معروف لكنه بلا محفظة (أو محفظة محذوفة) = رسائل
    // تلك المحفظة تُرفض بـ`no_source_template` رغم ظهور القالب.
    for (final original in all) {
      var t = original;
      var templateChanged = false;
      final jaibSharedId = 'tpl-default-jaib-ar-shared';
      if (t.id == jaibSharedId && t.pattern == _legacyJaibSharedPattern) {
        t = t.copyWith(
          pattern: _specFor('Jaib', 'ar-shared').pattern,
          sampleBody:
              'اضيف 100 ر.ي تحويل مشترك رص:10615 ر.ي من جارالله الكبودي 773086403',
        );
        templateChanged = true;
      }

      // v3: توحيد اسم قالب Jaib الإنجليزي.
      if (t.id == 'tpl-default-jaib-en-received' && t.name == 'JAIB — received (EN)') {
        t = t.copyWith(name: 'Jaib — received (EN)');
        templateChanged = true;
      }

      // v4: توحيد قيم senderCode للقوالب الافتراضية إلى قيم Sender ID الرسمية
      // بنفس حالة الأحرف والمسافات، دون المساس بأي قالب أنشأه المشغّل.
      if (t.id.startsWith('tpl-default-')) {
        final official = _officialSenderCodeForTemplateId(t.id);
        if (official != null && t.senderCode != official) {
          t = t.copyWith(senderCode: official);
          templateChanged = true;
        }
      }

      // v3: استبدال قوالب جوالي القديمة بقالب الاستلام المعتمد (واحد فقط).
      if (t.senderCode?.trim().toUpperCase() == 'JAWALI') {
        final jawaly = _specFor('Jawali', 'ar-received');
        // القالب الأساسي (shared أو ar-received) يُحدَّث للنمط الجديد.
        if (t.id == 'tpl-default-jawali-ar-shared' ||
            t.id == 'tpl-default-jawali-ar-received') {
          if (t.pattern != jawaly.pattern ||
              t.name != jawaly.name ||
              !t.isActive) {
            t = t.copyWith(
              name: jawaly.name,
              pattern: jawaly.pattern,
              sampleBody: jawaly.sampleBody,
              priority: jawaly.priority,
              isActive: true,
            );
            templateChanged = true;
          }
        } else if (t.id.startsWith('tpl-default-jawali-') && t.isActive) {
          // أوقف القوالب الافتراضية الزائدة.
          t = t.copyWith(isActive: false);
          templateChanged = true;
        }
      }

      final code = t.senderCode?.trim().toUpperCase();
      if (code == null || code.isEmpty) {
        if (templateChanged) {
          final saved = await templates.save(t);
          if (saved is Failure<void>) return Failure(saved.error);
          changed += 1;
        }
        continue;
      }
      final wallet = bySender[code];
      if (wallet == null) {
        if (templateChanged) {
          final saved = await templates.save(t);
          if (saved is Failure<void>) return Failure(saved.error);
          changed += 1;
        }
        continue;
      }
      final current = t.walletId?.trim();
      if (current != null && current.isNotEmpty && knownWalletIds.contains(current)) {
        if (templateChanged) {
          final saved = await templates.save(t);
          if (saved is Failure<void>) return Failure(saved.error);
          changed += 1;
        }
        continue;
      }
      final saved = await templates.save(t.copyWith(walletId: wallet.id));
      if (saved is Failure<void>) return Failure(saved.error);
      changed += 1;
    }

    if (!alreadySeeded) {
      await settings.save(
        AppSetting(key: seededKey, value: 'true', updatedAt: clock.now()),
      );
    }
    return Success(changed);
  }

  static _TplSpec _specFor(String walletKey, String variant) => _specs.firstWhere(
        (spec) => spec.walletKey == walletKey && spec.variant == variant,
      );

  static String? _officialSenderCodeForTemplateId(String id) {
    for (final spec in _specs) {
      final prefix =
          'tpl-default-${spec.senderCode.toLowerCase().replaceAll(' ', '-')}-';
      if (id.startsWith(prefix)) return spec.senderCode;
    }
    return null;
  }

  static const _specs = <_TplSpec>[
    // ── جيب — Jaib ────────────────────────────────────────────────────────
    _TplSpec(
      walletKey: 'Jaib',
      senderCode: 'Jaib',
      variant: 'ar-shared',
      name: 'جيب — تحويل مشترك',
      priority: 10,
      pattern:
          'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account} {phone}',
      sampleBody:
          'اضيف 500ر.ي تحويل مشترك رص:515920ر.ي من علي القواتي 715813555',
    ),
    _TplSpec(
      walletKey: 'Jaib',
      senderCode: 'Jaib',
      variant: 'ar-phone-only',
      name: 'جيب — تحويل (رقم بديل)',
      priority: 20,
      pattern: 'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {phone}',
      sampleBody: 'اضيف 500ر.ي تحويل مشترك رص:255265ر.ي من 8483883',
    ),
    _TplSpec(
      walletKey: 'Jaib',
      senderCode: 'Jaib',
      variant: 'ar-account-only',
      name: 'جيب — تحويل (اسم/Offline)',
      priority: 30,
      pattern: 'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}',
      sampleBody:
          'اضيف 200 ر.ي تحويل مشترك رص:414445 ر.ي من روضه نعمان اسم البعداني -77',
    ),
    _TplSpec(
      walletKey: 'Jaib',
      senderCode: 'Jaib',
      variant: 'en-received',
      name: 'Jaib — received (EN)',
      priority: 40,
      pattern: 'You have received {amount} YER from {phone} your balance {ref}',
      sampleBody: 'You have received 10 YER from 779776919 your balance 20',
    ),
    // ── جوالي — Jawali ───────────────────────────────────────────────────
    // قالب جوالي الوحيد المعتمد — يطابق رسائل الاستلام الفعلية.
    _TplSpec(
      walletKey: 'Jawali',
      senderCode: 'Jawali',
      variant: 'ar-received',
      name: 'جوالي — استلمت مبلغ',
      priority: 10,
      pattern: 'استلمت مبلغ {amount} YER من {phone} رصيدك هو.{ref}',
      sampleBody: 'استلمت مبلغ 200 YER من 733332303 رصيدك هو 245',
    ),
    // ── أم فلوس — MFloos ─────────────────────────────────────────────────
    _TplSpec(
      walletKey: 'MFloos',
      senderCode: 'MFloos',
      variant: 'ar-deposit',
      name: 'أم فلوس — إيداع',
      priority: 10,
      pattern: 'تم إيداع مبلغ {amount} YER من: {account} المرجع: {ref}',
      sampleBody:
          'تم إيداع مبلغ 300.00 YER من: منيره جبر المرجع:939493993',
    ),
    // ── فلوسك — Floosak ──────────────────────────────────────────────────
    _TplSpec(
      walletKey: 'Floosak',
      senderCode: 'Floosak',
      variant: 'ar-hawala',
      name: 'فلوسك — استلمت حوالة',
      priority: 10,
      pattern: 'استلمت حوالة من {account} بمبلغ {amount} ر.ي رصيدك {ref} ر.ي',
      sampleBody:
          'استلمت حوالة من بسام الشيباني بمبلغ 250.00 ر.ي رصيدك 250.00 ر.ي',
    ),
    _TplSpec(
      walletKey: 'Floosak',
      senderCode: 'Floosak',
      variant: 'ar-shared',
      name: 'فلوسك — تحويل مشترك',
      priority: 20,
      pattern:
          'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}',
      sampleBody:
          'اضيف 2000 ر.ي تحويل مشترك رص:2000 ر.ي من عميل-770000001',
    ),
    _TplSpec(
      walletKey: 'Floosak',
      senderCode: 'Floosak',
      variant: 'sms-generic',
      name: 'فلوسك — تحويل عام',
      priority: 30,
      pattern: 'تم استلام {amount} من {phone}',
      sampleBody: 'تم استلام 2000 من 770000001',
    ),
    // ── الكريمي — KuraimiLMB ─────────────────────────────────────────────
    _TplSpec(
      walletKey: 'KuraimiLMB',
      senderCode: 'KuraimiLMB',
      variant: 'ar-deposit',
      name: 'الكريمي — إيداع لحسابك',
      priority: 10,
      pattern: 'أودع/ {account} لحسابك مبلغ {amount} رصيدك {ref} YER',
      sampleBody:
          'أودع/احمد جابر حسن المنتصر لحسابك مبلغ 600 رصيدك 10030 YER',
    ),
    // ── ون كاش — ONE Cash ────────────────────────────────────────────────
    _TplSpec(
      walletKey: 'ONE Cash',
      senderCode: 'ONE Cash',
      variant: 'ar-received',
      name: 'ون كاش — استلمت',
      priority: 10,
      pattern: 'استملت {amount} من {account} رصيدك هوه {ref} ر.ي',
      sampleBody:
          'استملت 200.00 من وسام مرشد علي حمود رصيدك هوه 252.33 ر.ي',
    ),
    _TplSpec(
      walletKey: 'ONE Cash',
      senderCode: 'ONE Cash',
      variant: 'ar-shared',
      name: 'ون كاش — تحويل مشترك',
      priority: 20,
      pattern:
          'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}',
      sampleBody:
          'اضيف 1000 ر.ي تحويل مشترك رص:1000 ر.ي من عميل-771234567',
    ),
    _TplSpec(
      walletKey: 'ONE Cash',
      senderCode: 'ONE Cash',
      variant: 'ar-hawala',
      name: 'ون كاش — استلمت حوالة',
      priority: 30,
      pattern: 'استلمت حوالة من {account} بمبلغ {amount} ر.ي رصيدك {ref} ر.ي',
      sampleBody: 'استلمت حوالة من عميل بمبلغ 500.00 ر.ي رصيدك 1500.00 ر.ي',
    ),
    _TplSpec(
      walletKey: 'ONE Cash',
      senderCode: 'ONE Cash',
      variant: 'sms-generic',
      name: 'ون كاش — تحويل عام',
      priority: 40,
      pattern: 'تم استلام {amount} من {phone}',
      sampleBody: 'تم استلام 1000 من 771234567',
    ),
  ];
}

final class _TplSpec {
  const _TplSpec({
    required this.walletKey,
    required this.senderCode,
    required this.variant,
    required this.name,
    required this.priority,
    required this.pattern,
    required this.sampleBody,
  });

  /// مفتاح المحفظة الداخلي في [DefaultWalletSpecs].
  final String walletKey;

  /// قيمة `Sender ID` الرسمية المرتبطة بالقالب.
  final String senderCode;

  final String variant;
  final String name;
  final int priority;
  final String pattern;
  final String sampleBody;
}
