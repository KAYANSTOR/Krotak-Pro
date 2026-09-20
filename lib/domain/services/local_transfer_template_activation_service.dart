import '../../core/result.dart';
import '../entities/message.dart';
import '../repositories/repositories.dart';

/// Ensures at most one *active* transfer template per group.
///
/// Group key (highest wins):
/// 1. `pos:{posId}`
/// 2. `wallet:{walletId}`
/// 3. `sender:{normalized senderCode}`
/// 4. `unscoped`
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

  /// Persist [template] and, if it is active, deactivate every other
  /// template that shares the same [groupKey].
  Future<Result<void>> saveExclusive(TransferTemplate template) async {
    final listed = await templates.listAll();
    if (listed is Failure<List<TransferTemplate>>) {
      return Failure(listed.error);
    }
    final all = (listed as Success<List<TransferTemplate>>).value;
    final saved = await templates.save(template);
    if (saved is Failure<void>) return saved;
    if (!template.isActive) return const Success(null);

    final key = groupKey(template);
    for (final other in all) {
      if (other.id == template.id) continue;
      if (!other.isActive) continue;
      if (groupKey(other) != key) continue;
      final off = await templates.save(other.copyWith(isActive: false));
      if (off is Failure<void>) return off;
    }
    return const Success(null);
  }
}
