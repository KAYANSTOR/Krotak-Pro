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
