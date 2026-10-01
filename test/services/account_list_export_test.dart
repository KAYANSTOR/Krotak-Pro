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

  test('paged export applies the filter beyond the first page', () async {
    final candidates = [
      for (var i = 0; i < 5; i++)
        AccountExportCandidate(
          id: 'c$i',
          name: 'حساب $i',
          statusLabel: 'نشط',
          phone: '777$i',
          balanceMinor: i.isEven ? -100 : 100,
          provisional: false,
          merged: false,
        ),
      const AccountExportCandidate(
        id: 'merged',
        name: 'مدمج',
        statusLabel: 'مدمج',
        phone: '700',
        balanceMinor: -100,
        provisional: false,
        merged: true,
      ),
    ];
    final result = await loadFilteredAccountExport(
      filter: AccountExportFilter.debtor,
      pageSize: 2,
      page: (limit, offset) async =>
          candidates.skip(offset).take(limit).toList(growable: false),
    );
    expect(result.rows.map((row) => row.id), ['c0', 'c2', 'c4']);
    expect(result.truncated, isFalse);
    expect(result.pagesRead, 3);
    expect(result.rows.first.balanceYer, '-1.00');
  });

  test('paged export stops at the max row cap', () async {
    final result = await loadFilteredAccountExport(
      filter: AccountExportFilter.all,
      pageSize: 2,
      maxRows: 3,
      page: (limit, offset) async {
        if (offset > 6) return const [];
        return [
          for (var i = 0; i < limit; i++)
            AccountExportCandidate(
              id: 'c${offset + i}',
              name: 'حساب',
              statusLabel: 'نشط',
              phone: '',
              balanceMinor: 0,
              provisional: false,
              merged: false,
            ),
        ];
      },
    );
    expect(result.rows, hasLength(3));
    expect(result.truncated, isTrue);
  });
