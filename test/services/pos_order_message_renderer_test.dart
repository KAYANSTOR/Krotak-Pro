import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/pos_order_message_renderer.dart';

final class _Settings implements SettingsRepository {
  _Settings([Map<String, String>? values]) : _values = values ?? <String, String>{};

  final Map<String, String> _values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = _values[key];
    return Success(
      value == null
          ? null
          : AppSetting(
              key: key,
              value: value,
              updatedAt: DateTime.utc(2026, 9, 20),
            ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    _values[setting.key] = setting.value;
    return const Success(null);
  }
}

void main() {
  final pos = const PosAccount(
    posId: 'pos-1',
    customerId: 'pos-ledger-customer',
    name: 'بقالة الأمل',
    identifiers: <String>['777000111'],
    notifyPhone: '777000111',
  );

  const category = CardCategory(
    id: 'cat-100',
    name: '100 ميجا',
    faceValue: Money(minorUnits: 10000, currencyCode: 'YER'),
    isActive: true,
  );

  const cards = <Card>[
    Card(
      id: 'card-1',
      categoryId: 'cat-100',
      serialNumber: '100001',
      secretCode: '900001',
      status: CardStatus.sold,
    ),
    Card(
      id: 'card-2',
      categoryId: 'cat-100',
      serialNumber: '100002',
      secretCode: '900002',
      status: CardStatus.sold,
    ),
  ];

  test('renders customer voucher SMS and POS confirmation separately', () async {
    final renderer = PosOrderMessageRenderer(
      settings: _Settings(<String, String>{
        SettingKeys.networkName: 'NET',
      }),
    );

    final result = await renderer.render(
      posAccount: pos,
      customerPhone: '779776919',
      posNotificationPhone: '777000111',
      categoryName: category.name,
      faceValue: category.faceValue,
      unitCharge: const Money(minorUnits: 9000, currencyCode: 'YER'),
      cards: cards,
      quantity: 2,
    );

    expect(result, isA<Success<PosOrderMessages>>());
    final value = (result as Success<PosOrderMessages>).value;

    expect(value.customerDestination, '779776919');
    expect(value.posDestination, '777000111');
    expect(value.customerBody, contains('NET'));
    expect(value.customerBody, contains('100 ميجا'));
    expect(value.customerBody, contains('100001'));
    expect(value.customerBody, contains('900002'));
    expect(value.posBody, contains('779776919'));
    expect(value.posBody, contains('بقالة الأمل'));
    expect(value.posBody, contains('2 كروت'));
    expect(value.totalCharge.minorUnits, 18000);
  });

  test('uses persisted custom templates', () async {
    final renderer = PosOrderMessageRenderer(
      settings: _Settings(<String, String>{
        SettingKeys.networkName: 'شبكة كيان',
        SettingKeys.posCustomerCardDeliveryTemplate:
            'العميل {CUSTOMER_PHONE} — {NETWORK_NAME} — {cards}',
        SettingKeys.posOrderSuccessTemplate:
            'تم الطلب للعميل {CUSTOMER_PHONE} من {POS_NAME} بإجمالي {TOTAL} {CURRENCY}',
      }),
    );

    final result = await renderer.render(
      posAccount: pos,
      customerPhone: '733123456',
      posNotificationPhone: '777000111',
      categoryName: category.name,
      faceValue: category.faceValue,
      unitCharge: const Money(minorUnits: 8500, currencyCode: 'YER'),
      cards: <Card>[cards[0]],
      quantity: 1,
    );

    expect(result, isA<Success<PosOrderMessages>>());
    final value = (result as Success<PosOrderMessages>).value;
    expect(value.customerBody, startsWith('العميل 733123456'));
    expect(value.customerBody, contains('شبكة كيان'));
    expect(value.customerBody, contains('100001'));
    expect(value.posBody, 'تم الطلب للعميل 733123456 من بقالة الأمل بإجمالي 85 ر.ي');
  });
}
