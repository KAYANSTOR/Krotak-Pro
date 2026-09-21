import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/domain.dart';

import '../helpers/in_memory_repositories.dart';

void main() {
  late InMemoryCustomerRepository repo;

  setUp(() {
    repo = InMemoryCustomerRepository();
  });

  Future<void> seed({
    required String id,
    required String name,
    required String phone,
    CustomerStatus status = CustomerStatus.active,
    DateTime? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.utc(2026, 9, 20);
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

  test('suggestPhonesByPrefix returns matching active phones by prefix', () async {
    await seed(id: 'c1', name: 'أحمد', phone: '777123456', updatedAt: DateTime.utc(2026, 9, 19));
    await seed(id: 'c2', name: 'سارة', phone: '777999888', updatedAt: DateTime.utc(2026, 9, 20));
    await seed(id: 'c3', name: 'خالد', phone: '771111111', updatedAt: DateTime.utc(2026, 9, 18));

    final r = await repo.suggestPhonesByPrefix('777');
    expect(r, isA<Success<List<CustomerPhoneSuggestion>>>());
    final list = (r as Success<List<CustomerPhoneSuggestion>>).value;
    expect(list.length, 2);
    expect(list.first.phone, '777999888');
    expect(list.first.displayName, 'سارة');
    expect(list.map((e) => e.phone), isNot(contains('771111111')));
  });

  test('suggestPhonesByPrefix excludes blacklisted merged archived', () async {
    await seed(id: 'a', name: 'نشط', phone: '770000001');
    await seed(id: 'b', name: 'محظور', phone: '770000002', status: CustomerStatus.blacklisted);
    await seed(id: 'm', name: 'مدمج', phone: '770000003', status: CustomerStatus.merged);
    await seed(id: 'x', name: 'مؤرشف', phone: '770000004', status: CustomerStatus.archived);
    await seed(id: 'p', name: 'مؤقت', phone: '770000005', status: CustomerStatus.provisional);

    final r = await repo.suggestPhonesByPrefix('770');
    final list = (r as Success<List<CustomerPhoneSuggestion>>).value;
    final phones = list.map((e) => e.phone).toSet();
    expect(phones, containsAll(['770000001', '770000005']));
    expect(phones, isNot(contains('770000002')));
    expect(phones, isNot(contains('770000003')));
    expect(phones, isNot(contains('770000004')));
  });

  test('suggestPhonesByPrefix empty prefix returns empty', () async {
    await seed(id: 'c1', name: 'أ', phone: '777123456');
    final r = await repo.suggestPhonesByPrefix('');
    expect((r as Success<List<CustomerPhoneSuggestion>>).value, isEmpty);
  });

  test('suggestPhonesByPrefix respects limit', () async {
    for (var i = 0; i < 12; i++) {
      await seed(
        id: 'c$i',
        name: 'ع$i',
        phone: '77800${i.toString().padLeft(4, '0')}',
        updatedAt: DateTime.utc(2026, 9, 1).add(Duration(hours: i)),
      );
    }
    final r = await repo.suggestPhonesByPrefix('778', limit: 5);
    expect((r as Success<List<CustomerPhoneSuggestion>>).value.length, 5);
  });

  test('suggestPhonesByPrefix matches after canonical storage', () async {
    await seed(id: 'c1', name: 'يمني', phone: '0777123456');
    final r = await repo.suggestPhonesByPrefix('777');
    final list = (r as Success<List<CustomerPhoneSuggestion>>).value;
    expect(list, isNotEmpty);
    expect(list.first.phone, '777123456');
  });

  test('suggestPhonesByPrefix matches eastern arabic digits prefix', () async {
    await seed(id: 'c1', name: 'عربي', phone: '777123456');
    final r = await repo.suggestPhonesByPrefix('٧٧٧');
    final list = (r as Success<List<CustomerPhoneSuggestion>>).value;
    expect(list, isNotEmpty);
    expect(list.first.phone, '777123456');
  });

  test('PhoneNormalizer toWesternDigits converts eastern numerals', () {
    expect(PhoneNormalizer.toWesternDigits('٧٧٧١٢٣٤٥٦'), '777123456');
    expect(PhoneNormalizer.digitsOnly('٠٩٦٧٧٧٧'), '0967777');
  });

}
