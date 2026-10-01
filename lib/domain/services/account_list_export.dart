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
  bool truncated = false,
}) {
  final buf = StringBuffer('\uFEFF');
  buf.writeln('filter,${accountCsvCell(filterLabel)}');
  buf.writeln('truncated,${truncated ? 'yes' : 'no'}');
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


/// فلتر التصدير نفسه المعروض في شاشة الحسابات.
enum AccountExportFilter { all, debtor, creditor, zero, provisional, unlinked }

/// مرشّح حساب بعد قراءة الرصيد والهاتف، مستقل عن صفوف الواجهة المحمّلة.
class AccountExportCandidate {
  const AccountExportCandidate({
    required this.id,
    required this.name,
    required this.statusLabel,
    required this.phone,
    required this.balanceMinor,
    required this.provisional,
    required this.merged,
  });

  final String id;
  final String name;
  final String statusLabel;
  final String phone;
  final int balanceMinor;
  final bool provisional;
  final bool merged;

  AccountExportRow toRow() {
    return AccountExportRow(
      id: id,
      name: name,
      statusLabel: statusLabel,
      phone: phone,
      balanceYer: (balanceMinor / 100).toStringAsFixed(2),
      provisional: provisional,
    );
  }
}

bool matchesAccountExportFilter(
  AccountExportFilter filter,
  AccountExportCandidate candidate,
) {
  if (candidate.merged) return false;
  return switch (filter) {
    AccountExportFilter.all => true,
    AccountExportFilter.debtor => candidate.balanceMinor < 0,
    AccountExportFilter.creditor => candidate.balanceMinor > 0,
    AccountExportFilter.zero => candidate.balanceMinor == 0,
    AccountExportFilter.provisional => candidate.provisional,
    AccountExportFilter.unlinked => candidate.phone.trim().isEmpty,
  };
}

class AccountExportLoadResult {
  const AccountExportLoadResult({
    required this.rows,
    required this.truncated,
    required this.pagesRead,
  });

  final List<AccountExportRow> rows;
  final bool truncated;
  final int pagesRead;
}

/// يجمع كل الصفحات المطابقة للبحث ثم يطبّق الفلتر، بحد أعلى حتى لا يُصدَّر جزء الشاشة فقط.
Future<AccountExportLoadResult> loadFilteredAccountExport({
  required AccountExportFilter filter,
  required Future<List<AccountExportCandidate>> Function(int limit, int offset) page,
  int pageSize = 200,
  int maxRows = 5000,
}) async {
  final rows = <AccountExportRow>[];
  var offset = 0;
  var pagesRead = 0;
  var truncated = false;
  while (rows.length < maxRows) {
    final batch = await page(pageSize, offset);
    pagesRead += 1;
    if (batch.isEmpty) break;
    for (final candidate in batch) {
      if (!matchesAccountExportFilter(filter, candidate)) continue;
      rows.add(candidate.toRow());
      if (rows.length >= maxRows) {
        truncated = true;
        break;
      }
    }
    if (batch.length < pageSize) break;
    offset += pageSize;
    if (pagesRead > 1000) {
      truncated = true;
      break;
    }
  }
  return AccountExportLoadResult(
    rows: rows,
    truncated: truncated,
    pagesRead: pagesRead,
  );
}
