import '../../core/result.dart';
import '../entities/advance.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/license.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../entities/transaction.dart';
import '../entities/wallet.dart';

abstract interface class CustomerRepository {
  Future<Result<Customer?>> findById(String id);
  Future<Result<Customer?>> findByIdentifier(String value);
  Future<Result<List<Customer>>> search(String query);

  /// اقتراح أرقام جوال بالبادئة أثناء الكتابة (بيع مباشر).
  /// يعيد أرقاماً مطبّعة مع الاسم والحالة، مرتبة بالأحدث، بدون حسابات موقوفة/مدمجة/مؤرشفة.
  /// [limit] يمنع N+1 واستعلامات ثقيلة.
  Future<Result<List<CustomerPhoneSuggestion>>> suggestPhonesByPrefix(
    String prefix, {
    int limit = 8,
  });

  Future<Result<List<CustomerIdentifier>>> listIdentifiers(String customerId);

  /// قائمة حسابات بلقطة مجمّعة (رصيد + هاتف) بثلاثة استعلامات بدل N+1.
  /// [limit]/[offset] بعد استبعاد الحسابات المدمجة حتى لا تُقرأ كل الصفوف.
  Future<Result<List<CustomerAccountSnapshot>>> listAccountSnapshots({
    String query = '',
    String currencyCode = 'YER',
    int? limit,
    int offset = 0,
  });

  Future<Result<void>> save(Customer customer);
  Future<Result<void>> saveIdentifier(CustomerIdentifier identifier);
}
