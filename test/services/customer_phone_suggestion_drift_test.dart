import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, CustomerIdentifier;
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/phone_normalizer.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository repo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repo = LocalCustomerRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seed({
    required String id,
    required String name,
    required String phone,
    CustomerStatus status = CustomerStatus.active,
    DateTime? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.utc(2026, 9, 21);
    await repo.save(
      Customer(
        id: id,
        displayName: name,
        status: status,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      ),
    );
    await repo.saveIdentifier(
      CustomerIdentifier(
        id: 'id-$id',
        customerId: id,
        type: CustomerIdentifierType.phoneNumber,
        value: PhoneNormalizer.forStorage(phone, asPhone: true),
        isPrimary: true,
      ),
    );
  }

  test('drift suggestPhonesByPrefix matches prefix and newest first', () async {
    await seed(id: 'c1', name: 'أحمد', phone: '777123456', updatedAt: DateTime.utc(2026, 9, 19));
    await seed(id: 'c2', name: 'سارة', phone: '777999888', updatedAt: DateTime.utc(2026, 9, 20));
    await seed(id: 'c3', name: 'خالد', phone: '771111111', updatedAt: DateTime.utc(2026, 9, 18));

    final r = await repo.suggestPhonesByPrefix('777');
    final list = (r as Success<List<CustomerPhoneSuggestion>>).value;
    expect(list.length, 2);
    expect(list.first.phone, '777999888');
    expect(list.first.displayName, 'سارة');
  });

  test('drift suggestPhonesByPrefix excludes blocked statuses', () async {
    await seed(id: 'a', name: 'نشط', phone: '770000001');
    await seed(id: 'b', name: 'محظور', phone: '770000002', status: CustomerStatus.blacklisted);
    await seed(id: 'p', name: 'مؤقت', phone: '770000005', status: CustomerStatus.provisional);

    final list = ((await repo.suggestPhonesByPrefix('770')) as Success<List<CustomerPhoneSuggestion>>).value;
    expect(list.map((e) => e.phone).toSet(), {'770000001', '770000005'});
  });
}
