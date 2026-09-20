import '../../core/result.dart';
import '../entities/card.dart';
import '../entities/money.dart';
import '../entities/pos_account.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// Renders the two outbound SMS messages produced by a POS card order.
final class PosOrderMessageRenderer {
  const PosOrderMessageRenderer({required this.settings});

  final SettingsRepository settings;

  Future<Result<PosOrderMessages>> render({
    required PosAccount posAccount,
    required String customerPhone,
    required String posNotificationPhone,
    required String categoryName,
    required Money faceValue,
    required Money unitCharge,
    required List<Card> cards,
    required int quantity,
  }) async {
    if (cards.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'pos_order_cards_missing',
          message: 'POS order has no cards to deliver',
        ),
      );
    }

    final customerTemplate = await _template(
      SettingKeys.posCustomerCardDeliveryTemplate,
      SettingDefaults.posCustomerCardDeliveryTemplate,
    );
    if (customerTemplate is Failure<String>) return Failure(customerTemplate.error);

    final posTemplate = await _template(
      SettingKeys.posOrderSuccessTemplate,
      SettingDefaults.posOrderSuccessTemplate,
    );
    if (posTemplate is Failure<String>) return Failure(posTemplate.error);

    final networkResult = await settings.find(SettingKeys.networkName);
    final networkName = networkResult is Success<AppSetting?> &&
            (networkResult.value?.value.trim().isNotEmpty ?? false)
        ? networkResult.value!.value.trim()
        : SettingDefaults.networkName;

    final effectiveQty = cards.length;
    final totalCharge = Money(
      minorUnits: unitCharge.minorUnits * effectiveQty,
      currencyCode: unitCharge.currencyCode,
    );

    final cardBlocks = cards.map((card) {
      final serial = card.serialNumber.trim();
      final secret = card.secretCode.trim();
      if (secret.isEmpty) return 'رقم الكرت: $serial';
      return 'رقم الكرت: $serial\nالرمز: $secret';
    }).join('\n\n');

    final first = cards.first;
    final quantityText = _quantityText(effectiveQty);
    final customerBody = _replace(
      (customerTemplate as Success<String>).value,
      <String, String>{
        'serial': first.serialNumber,
        'code': first.secretCode,
        'secret': first.secretCode,
        'SECRET': first.secretCode,
        'CODE': first.secretCode,
        'CARD_CODE': first.serialNumber,
        'CARD_VALUE': _money(faceValue),
        'CURRENCY': _currency(faceValue),
        'NETWORK_NAME': networkName,
        'network': networkName,
        'network_name': networkName,
        'category': categoryName,
        'category_name': categoryName,
        'phone': customerPhone,
        'customer_phone': customerPhone,
        'QUANTITY': '$effectiveQty',
        'quantity': '$effectiveQty',
        'QUANTITY_TEXT': quantityText,
        'quantity_text': quantityText,
        'cards': cardBlocks,
        'CARDS': cardBlocks,
      },
    );

    final posBody = _replace(
      (posTemplate as Success<String>).value,
      <String, String>{
        'pos': posAccount.name,
        'POS_NAME': posAccount.name,
        'pos_name': posAccount.name,
        'CUSTOMER_PHONE': customerPhone,
        'customer_phone': customerPhone,
        'phone': customerPhone,
        'destination': customerPhone,
        'CARD_VALUE': _money(faceValue),
        'category': categoryName,
        'category_name': categoryName,
        'CURRENCY': _currency(faceValue),
        'QUANTITY': '$effectiveQty',
        'quantity': '$effectiveQty',
        'QUANTITY_TEXT': quantityText,
        'quantity_text': quantityText,
        'AMOUNT': _money(unitCharge),
        'amount': _money(unitCharge),
        'TOTAL': _money(totalCharge),
        'total': _money(totalCharge),
        'NOTIFY_PHONE': posNotificationPhone,
        'notify_phone': posNotificationPhone,
        'NETWORK_NAME': networkName,
        'network': networkName,
        'network_name': networkName,
        'pos_id': posAccount.posId,
      },
    );

    return Success(
      PosOrderMessages(
        customerBody: customerBody,
        posBody: posBody,
        customerDestination: customerPhone,
        posDestination: posNotificationPhone,
        quantity: effectiveQty,
        totalCharge: totalCharge,
      ),
    );
  }

  Future<Result<String>> _template(String key, String fallback) async {
    final result = await settings.find(key);
    if (result is Failure<AppSetting?>) return Failure(result.error);
    final value = (result as Success<AppSetting?>).value?.value.trim();
    return Success(value == null || value.isEmpty ? fallback : value);
  }

  String _replace(String body, Map<String, String> values) {
    var result = body;
    for (final entry in values.entries) {
      result = result.replaceAll('{' + entry.key + '}', entry.value);
      result = result.replaceAll('%' + entry.key, entry.value);
    }
    return result.trim();
  }

  String _currency(Money money) =>
      money.currencyCode == 'YER' ? 'ر.ي' : money.currencyCode;

  String _money(Money money) {
    final major = money.minorUnits / 100;
    if (major == major.roundToDouble()) return major.toInt().toString();
    return major.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  String _quantityText(int quantity) {
    if (quantity == 1) return 'الكرت';
    if (quantity == 2) return 'كرتين';
    return '$quantity كروت';
  }
}

final class PosOrderMessages {
  const PosOrderMessages({
    required this.customerBody,
    required this.posBody,
    required this.customerDestination,
    required this.posDestination,
    required this.quantity,
    required this.totalCharge,
  });

  final String customerBody;
  final String posBody;
  final String customerDestination;
  final String posDestination;
  final int quantity;
  final Money totalCharge;
}
