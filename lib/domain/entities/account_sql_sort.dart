/// ترتيب قائمة الحسابات داخل SQL حتى يبقى حد الصفحة والتصدير عالمياً.
enum AccountSqlSort { balanceDesc, balanceAsc, name, newest }

String accountSqlOrderBy(AccountSqlSort sort, {String balanceAlias = 'bal'}) {
  final alias = balanceAlias == 'disp' ? 'disp' : 'bal';
  switch (sort) {
    case AccountSqlSort.balanceDesc:
      return 'COALESCE($alias.signed_balance, 0) DESC, c.display_name, c.id';
    case AccountSqlSort.balanceAsc:
      return 'COALESCE($alias.signed_balance, 0) ASC, c.display_name, c.id';
    case AccountSqlSort.name:
      return 'c.display_name, c.id';
    case AccountSqlSort.newest:
      return 'c.created_at DESC, c.display_name, c.id';
  }
}
