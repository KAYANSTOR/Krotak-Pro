import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';

void main() {
  test('empty draft falls back so the offer template is never blank', () {
    expect(
      PromotionRewardTemplate.normalize('   ', fallback: 'افتراضي'),
      'افتراضي',
    );
    expect(
      PromotionRewardTemplate.normalize(null, fallback: 'افتراضي'),
      'افتراضي',
    );
  });

  test('typed body is kept after trim', () {
    expect(
      PromotionRewardTemplate.normalize('  مكافأة {title}  ', fallback: 'x'),
      'مكافأة {title}',
    );
  });

  test('unknown placeholders are reported once', () {
    expect(
      PromotionRewardTemplate.unknownPlaceholders(
        '{title} {serial_number} {serial_number} {secret}',
      ),
      ['serial_number'],
    );
  });
}
