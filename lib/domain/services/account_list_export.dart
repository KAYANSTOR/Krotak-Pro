/// تصدير قائمة الحسابات المفلترة دون الاعتماد على الواجهة.
library;

/// صف تصدير واحد مبني من اللقطة المعروضة بعد الفلتر والبحث.
class AccountExportRow {
  const AccountExportRow({
    required this.id,
    required this.name,
    required this.statusLabel,
    required this.phone,
    required this.balanceYer,
    required this.provisional,
  });

  final String id;
  final String name;
  final String statusLabel;
  final String phone;
  final String balanceYer;
  final bool provisional;
}

/// يهرّب خلية CSV ويمنع حقن الصيغ في Excel.
String accountCsvCell(String value) {
  var cell = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
  if (cell.startsWith('=') ||
      cell.startsWith('+') ||
      cell.startsWith('-') ||
      cell.startsWith('@')) {
    cell = "'$cell";
  }
  final needsQuote =
      cell.contains(',') || cell.contains('"') || cell.startsWith("'");
  if (needsQuote) {
    return '"${cell.replaceAll('"', '""')}"';
  }
  return cell;
}

/// CSV بترويسة عربية وبادئة BOM ليُفتح في Excel بالاتجاه الصحيح.
String buildAccountListCsv({
  required String filterLabel,
  required List<AccountExportRow> rows,
}) {
  final buf = StringBuffer('\uFEFF');
  buf.writeln('filter,${accountCsvCell(filterLabel)}');
  buf.writeln('id,name,status,phone,balance_yer,provisional');
  for (final row in rows) {
    buf.writeln([
      accountCsvCell(row.id),
      accountCsvCell(row.name),
      accountCsvCell(row.statusLabel),
      accountCsvCell(row.phone),
      accountCsvCell(row.balanceYer),
      row.provisional ? 'yes' : 'no',
    ].join(','));
  }
  return buf.toString();
}
