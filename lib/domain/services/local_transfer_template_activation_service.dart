import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// تفعيل/إيقاف قوالب التحويل **دون إلغاء القوالب الأخرى لنفس المصدر**.
///
/// كان هذا الـservice سابقاً يُبقي قالباً واحداً نشطاً لكل مجموعة
/// (`pos:` / `wallet:` / `sender:`)، فكان تبديل مفتاح قالب واحد يُوقف بقية
/// القوالب — وهذا خطأ لأنه يُعطّل الاستقبال: نقطة البيع الواحدة تحتاج قوالب
/// نشطة متعددة في الوقت نفسه (طلب كرت، عدة كروت، رقم تسليم، طلب رصيد…)،
/// و[LocalMessageParser] يختار الأنسب حسب `priority` بين كل القوالب النشطة.
///
/// بقيت `groupKey` لأنها التجميع الطبيعي لمصدر واحد: تُستخدم الآن لعمليات
/// جماعية (تفعيل الكل / إيقاف الكل / عدّ النشط) بدل فرض قالب واحد.
final class LocalTransferTemplateActivationService {
  const LocalTransferTemplateActivationService(this.templates);

  final TransferTemplateRepository templates;

  static String groupKey(TransferTemplate t) {
    final pos = t.posId?.trim();
    if (pos != null && pos.isNotEmpty) return 'pos:$pos';
    final wallet = t.walletId?.trim();
    if (wallet != null && wallet.isNotEmpty) return 'wallet:$wallet';
    final sender = t.senderCode?.trim().toLowerCase();
    if (sender != null && sender.isNotEmpty) return 'sender:$sender';
    return 'unscoped';
  }

  /// حفظ قالب واحد كما هو — لا يمسّ حالة أي قالب آخر.
  Future<Result<void>> save(TransferTemplate template) {
    return templates.save(template);
  }

  /// تفعيل (أو إيقاف) **كل** قوالب مصدر واحد بضغطة واحدة.
  ///
  /// يُرجع عدد القوالب التي تغيّرت فعلاً، فلا يُكتب صف بلا تغيير.
  Future<Result<int>> setGroupActive({
    required String key,
    required bool isActive,
  }) async {
    final listed = await templates.listAll();
    if (listed is Failure<List<TransferTemplate>>) return Failure(listed.error);
    var changed = 0;
    for (final t in (listed as Success<List<TransferTemplate>>).value) {
      if (groupKey(t) != key) continue;
      if (t.isActive == isActive) continue;
      final saved = await templates.save(t.copyWith(isActive: isActive));
      if (saved is Failure<void>) return Failure(saved.error);
      changed += 1;
    }
    return Success(changed);
  }

  /// عدد القوالب النشطة مقابل كل قوالب المصدر — لعرض «3 من 11 نشط».
  Future<Result<({int active, int total})>> groupCounts(String key) async {
    final listed = await templates.listAll();
    if (listed is Failure<List<TransferTemplate>>) return Failure(listed.error);
    var active = 0;
    var total = 0;
    for (final t in (listed as Success<List<TransferTemplate>>).value) {
      if (groupKey(t) != key) continue;
      total += 1;
      if (t.isActive) active += 1;
    }
    return Success((active: active, total: total));
  }
}
