import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/account_list_export.dart';

void main() {
  test('account csv escapes formulas and records the active filter', () {
    final csv = buildAccountListCsv(
      filterLabel: 'مدين',
      rows: const [
        AccountExportRow(
          id: 'c1',
          name: '=cmd',
          statusLabel: 'نشط',
          phone: '777',
          balanceYer: '-10.00',
          provisional: false,
        ),
      ],
    );
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('filter,مدين'));
    expect(csv, contains("\"'=cmd\""));
    expect(csv, contains('-10.00'));
    expect(csv, isNot(contains(',=cmd,')));
  });
}
