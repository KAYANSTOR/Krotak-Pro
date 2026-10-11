import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// القسم 5.4 — بوابة تغطية: كل عنصر في الجرد الآلي له صف في مصفوفة الأزرار،
/// وبلا أي صف بحالة «مجهول»، والفئة ضمن A..G.
///
/// المصفوفة تُولَّد بـ`tools/audit_buttons_matrix.py`.
void main() {
  test('كل عناصر الجرد لها صف في المصفوفة وبلا حالة مجهولة', () {
    const allowedStatus = <String>{
      'يعمل',
      'مُصلَح',
      'ناقص-مؤجل بسبب',
      'يحتاج جهاز',
    };
    const allowedCategory = <String>{'A', 'B', 'C', 'D', 'E', 'F', 'G'};

    final inventory = _readCsv('docs/audit/interactive-inventory.csv');
    expect(inventory, isNotEmpty, reason: 'الجرد الآلي مفقود أو فارغ');

    final dir = Directory('docs/audit');
    final matrices = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('buttons-matrix-'))
        .toList();
    expect(matrices, hasLength(1),
        reason: 'يجب وجود ملف مصفوفة واحد docs/audit/buttons-matrix-*.csv');

    final matrix = _readCsv(
      'docs/audit/${matrices.single.uri.pathSegments.last}',
    );

    expect(matrix.length, inventory.length,
        reason: 'عدد صفوف المصفوفة لا يطابق عدد صفوف الجرد');

    final inventoryKeys = inventory
        .map((r) => '${r['file']}:${r['line']}')
        .toSet();
    final matrixKeys = matrix.map((r) => r['file_line']).toSet();
    expect(matrixKeys, inventoryKeys,
        reason: 'عناصر المصفوفة لا تطابق عناصر الجرد (file:line)');

    for (final row in matrix) {
      final status = row['status'] ?? '';
      expect(status.trim(), isNotEmpty,
          reason: 'صف بلا حالة: ${row['id']}');
      expect(allowedStatus, contains(status),
          reason: 'حالة غير معروفة في ${row['id']}: $status');
      expect(allowedCategory, contains(row['category']),
          reason: 'فئة غير معروفة في ${row['id']}: ${row['category']}');
    }
  });
}

/// قارئ CSV بسيط يدعم الحقول المحاطة بعلامات اقتباس.
List<Map<String, String>> _readCsv(String path) {
  final file = File(path);
  if (!file.existsSync()) return const <Map<String, String>>[];
  final lines = file.readAsStringSync().split(RegExp(r'\r?\n'));
  if (lines.isEmpty || lines.first.trim().isEmpty) {
    return const <Map<String, String>>[];
  }
  final header = _splitCsv(lines.first);
  final rows = <Map<String, String>>[];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final cells = _splitCsv(line);
    final map = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      map[header[i]] = i < cells.length ? cells[i] : '';
    }
    rows.add(map);
  }
  return rows;
}

List<String> _splitCsv(String line) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      cells.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  cells.add(buffer.toString());
  return cells;
}
