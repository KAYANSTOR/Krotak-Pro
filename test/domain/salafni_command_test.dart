import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/salafni_command.dart';

void main() {
  test('parses amount-specific salafni commands in western and eastern digits', () {
    expect(SalafniCommand.tryParse('سلفني 100')?.amountMinorUnits, 10000);
    expect(SalafniCommand.tryParse('سلفني 200')?.amountMinorUnits, 20000);
    expect(SalafniCommand.tryParse('سلفني 250')?.amountMinorUnits, 25000);
    expect(SalafniCommand.tryParse('سلفني ٢٥٠')?.amountMinorUnits, 25000);
    expect(SalafniCommand.tryParse('salafni 100')?.amountMinorUnits, 10000);
    expect(SalafniCommand.tryParse('س 100')?.amountMinorUnits, 10000);
    expect(SalafniCommand.tryParse('  سلفني   100.50  ')?.amountMinorUnits, 10050);
  });

  test('keeps the bare command and rejects extra text or other categories', () {
    expect(SalafniCommand.tryParse('سلفني')?.amountMinorUnits, isNull);
    expect(SalafniCommand.tryParse('s'), isNotNull);
    expect(SalafniCommand.tryParse('سلفني 100 إضافي'), isNull);
    expect(SalafniCommand.tryParse('تم استلام 100'), isNull);
    expect(SalafniCommand.tryParse('سلفني 0'), isNull);
  });
}
