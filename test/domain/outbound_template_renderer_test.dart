import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/outbound_template_renderer.dart';

void main() {
  test('strict render succeeds when all placeholders resolved', () {
    final r = OutboundTemplateRenderer.renderStrict(
      template: 'رقم الكرت: {serial}\nالرمز: {code}',
      values: {'serial': '111', 'code': '222'},
    );
    expect(r.isSuccess, isTrue);
    expect((r as dynamic).value, contains('111'));
  });

  test('strict render fails on unresolved placeholder', () {
    final r = OutboundTemplateRenderer.renderStrict(
      template: 'كرت {serial_number} والرمز {code}',
      values: {'serial': '111', 'code': '222'},
    );
    expect(r.isFailure, isTrue);
    final err = (r as dynamic).error;
    expect(err.code, 'outbound_unresolved_placeholder');
    expect(err.message, contains('serial_number'));
  });

  test('unresolvedPlaceholders lists remaining tokens', () {
    final left = OutboundTemplateRenderer.unresolvedPlaceholders(
      'hello {a} and {b} and {a}',
    );
    expect(left.toSet(), {'a', 'b'});
  });
}
