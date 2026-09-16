from pathlib import Path
p = Path('lib/ui/screens/inventory_sheets.dart')
t = p.read_text()
replacements = [
    ("Text('Name required'", "Text('أدخل اسم الفئة'"),
    ("Text('Value must be > 0'", "Text('أدخل قيمة اسمية صحيحة أكبر من صفر'"),
    ("Text('Category saved'", "Text('تم إنشاء الفئة'"),
]
changed = False
for a, b in replacements:
    if a in t:
        t = t.replace(a, b)
        changed = True
        print('replaced', a[:30])
if changed:
    p.write_text(t)
    print('category arabic applied')
else:
    print('already arabic or patterns missing')
