import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/net/net_indicators.dart';
import 'package:net_app/ui/widgets/net/net_service_tile.dart';
import 'package:net_app/ui/widgets/net/net_transaction_detail_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildKayanLightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('NetServiceTile shows its label and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        NetServiceTile(
          label: 'الحسابات',
          icon: Icons.groups_rounded,
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('الحسابات'), findsOneWidget);
    await tester.tap(find.text('الحسابات'));
    expect(taps, 1);
  });

  testWidgets('NetServiceGrid lays out every tile', (tester) async {
    await tester.pumpWidget(
      _wrap(
        NetServiceGrid(
          tiles: [
            for (var i = 0; i < 9; i++)
              NetServiceTile(
                label: 'خدمة $i',
                icon: Icons.circle_outlined,
                onTap: () {},
              ),
          ],
        ),
      ),
    );
    expect(find.byType(NetServiceTile), findsNWidgets(9));
    expect(find.text('خدمة 0'), findsOneWidget);
  });

  testWidgets('NetHorizontalBars renders rows and the empty state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const NetHorizontalBars(
          data: [
            NetBarDatum(
              label: 'حساب أ',
              value: 100,
              color: Color(0xFF059669),
              valueLabel: '100 ر.ي',
            ),
            NetBarDatum(
              label: 'حساب ب',
              value: 40,
              color: Color(0xFFD93838),
              valueLabel: '40 ر.ي',
            ),
          ],
        ),
      ),
    );
    expect(find.byType(NetBarRow), findsNWidgets(2));
    expect(find.text('حساب أ'), findsOneWidget);
    expect(find.text('40 ر.ي'), findsOneWidget);

    await tester.pumpWidget(_wrap(const NetHorizontalBars(data: [])));
    expect(find.text('لا توجد بيانات لعرضها'), findsOneWidget);
  });

  testWidgets('NetIndicatorGrid renders every indicator', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const NetIndicatorGrid(
          indicators: [
            NetIndicatorTile(label: 'الحسابات', value: '3', icon: Icons.groups_rounded),
            NetIndicatorTile(label: 'غير مربوط', value: '1', icon: Icons.link_off_rounded),
          ],
        ),
      ),
    );
    expect(find.byType(NetIndicatorTile), findsNWidgets(2));
    expect(find.text('الحسابات'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('NetTransactionDetailSheet shows the transaction data', (tester) async {
    final transaction = Transaction(
      id: 'tx-42',
      type: TransactionType.deposit,
      status: TransactionStatus.completed,
      amount: const Money(minorUnits: 10000, currencyCode: 'YER'),
      createdAt: DateTime(2026, 9, 18, 3, 49),
      reference: '17902153066372',
    );

    await tester.pumpWidget(
      _wrap(NetTransactionDetailSheet(transaction: transaction)),
    );
    await tester.pump();

    expect(find.text('بيانات الحركة'), findsOneWidget);
    expect(find.text('17902153066372'), findsOneWidget);
    expect(find.text('إيداع / تحويل'), findsOneWidget);
    expect(find.text('مكتملة'), findsOneWidget);
    expect(find.text('مشاركة'), findsOneWidget);
    expect(find.text('حفظ نص'), findsOneWidget);
    expect(find.text('حفظ صورة'), findsOneWidget);
    expect(find.text('غير مرتبط بحساب'), findsOneWidget);
  });
}
