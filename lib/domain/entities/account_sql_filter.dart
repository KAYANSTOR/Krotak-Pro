/// فلتر قائمة الحسابات الذي يُطبَّق داخل SQL لا بعد تحميل الصفوف.
enum AccountSqlFilter { all, debtor, creditor, zero, provisional, unlinked }

/// عدّادات كل شرائح الحسابات من استعلام واحد، لنفس البحث.
final class AccountFilterCounts {
  const AccountFilterCounts({
    required this.all,
    required this.debtor,
    required this.creditor,
    required this.zero,
    required this.provisional,
    required this.unlinked,
  });

  final int all;
  final int debtor;
  final int creditor;
  final int zero;
  final int provisional;
  final int unlinked;

  int operator [](AccountSqlFilter filter) => switch (filter) {
        AccountSqlFilter.all => all,
        AccountSqlFilter.debtor => debtor,
        AccountSqlFilter.creditor => creditor,
        AccountSqlFilter.zero => zero,
        AccountSqlFilter.provisional => provisional,
        AccountSqlFilter.unlinked => unlinked,
      };
}



/// إجمالي الأرصدة المدينة والدائنة لنفس البحث والشريحة، بلا حد الصفحة.
/// المدين = مجموع الأرصدة السالبة بالقيمة المطلقة. الدائن = مجموع الموجبة.
/// يستبعد المدمج ويتجاهل الحركات غير المكتملة.
final class AccountLedgerTotals {
  const AccountLedgerTotals({
    required this.debtorMinorUnits,
    required this.creditorMinorUnits,
  });

  final int debtorMinorUnits;
  final int creditorMinorUnits;
}

/// إجمالي المدين والدائن لعملة واحدة ضمن نفس شريحة الحسابات.
/// عضوية الشريحة تُحسب من رصيد الريال اليمني حتى تبقى البطاقات مطابقة للقائمة.
final class AccountCurrencyLedgerTotals {
  const AccountCurrencyLedgerTotals({
    required this.currencyCode,
    required this.debtorMinorUnits,
    required this.creditorMinorUnits,
  });

  final String currencyCode;
  final int debtorMinorUnits;
  final int creditorMinorUnits;
}

String _minorLabel(int minorUnits) {
  final negative = minorUnits < 0;
  final absUnits = minorUnits.abs();
  final whole = absUnits ~/ 100;
  final fraction = (absUnits % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}

/// سطر العملات غير الريال اليمني. فارغ إن لم توجد حركة مكتملة بغير YER.
String otherCurrencyTotalsLabel(List<AccountCurrencyLedgerTotals> rows) {
  final others = rows.where(
    (row) =>
        row.currencyCode != 'YER' &&
        (row.debtorMinorUnits != 0 || row.creditorMinorUnits != 0),
  );
  if (others.isEmpty) return '';
  return others
      .map(
        (row) =>
            '${row.currencyCode}: مدين ${_minorLabel(row.debtorMinorUnits)} / دائن ${_minorLabel(row.creditorMinorUnits)}',
      )
      .join(' · ');
}
