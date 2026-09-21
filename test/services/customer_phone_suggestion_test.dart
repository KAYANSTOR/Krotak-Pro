import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/customer.dart';

import '../helpers/in_memory_repositories.dart';

void main() {
  late InMemoryCustomerRepository customers;

  setUp(() {
    customers = InMemoryCustomerRepository();
  });

  Future<void> seed({
    required String id,
    required String name,
    required String phone,
    CustomerStatus status = CustomerStatus.active,
    DateTime? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.utc(2026, 9, 21);
    await customers.save(
      Customer(
        id: id,
        displayName: name,
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await customers.saveIdentifier(
      CustomerIdentifier(
        id: 'id-$id',
        customerId: id,
        type: CustomerIdentifierType.phoneNumber,
        value: phone,
        isPrimary: true,
      ),
    );
  }

  test('prefix match returns phone + name and skips blacklisted', () async {
    await seed(id: 'c1', name: 'أحمد', phone: '777123456');
    await seed(id: 'c2', name: 'سالم', phone: '777999000');
    await seed(
      id: 'c3',
      name: 'موقوف',
      phone: '777111222',
      status: CustomerStatus.blacklisted,
    );

    final r = await customers.suggestPhonesByPrefix('7771');
    expect(r, isA<Success<List<CustomerPhoneSuggestion>>>());
    final list = (r as Success<List<CustomerPhoneSuggestion>>).value;
    expect(list.map((e) => e.phone), ['777123456']);
    expect(list.single.displayName, 'أحمد');
    expect(list.single.isSellable, isTrue);
  });

  test('empty or non-digit prefix returns empty without error', () async {
    await seed(id: 'c1', name: 'أحمد', phone: '777123456');
    final empty = await customers.suggestPhonesByPrefix('   ');
    expect((empty as Success<List<CustomerPhoneSuggestion>>).value, isEmpty);
  });

  test('limit caps result size', () async {
    for (var i = 0; i < 12; i++) {
      await seed(
        id: 'c$i',
        name: 'C$i',
        phone: '77000000$i'.substring(0, 9),
        updatedAt: DateTime.utc(2026, 9, 21).add(Duration(minutes: i)),
      );
    }
    final r = await customers.suggestPhonesByPrefix('77', limit: 3);
    expect((r as Success<List<CustomerPhoneSuggestion>>).value.length, 3);
  });
}
