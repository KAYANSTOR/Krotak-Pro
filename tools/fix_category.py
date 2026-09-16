from pathlib import Path
p = Path('lib/ui/screens/inventory_sheets.dart')
t = p.read_text()
old = 'if (name.isEmpty || major == null || major <= 0) return;'
new = '''if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name required', style: TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    if (major == null || major <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Value must be > 0', style: TextStyle(fontFamily: 'Tajawal'))));
      return;
    }'''
if old in t:
    t = t.replace(old, new)
    print('validation fixed')
else:
    print('validation pattern missing')
old2 = 'await widget.onChanged();\n    if (context.mounted) Navigator.pop(context);'
new2 = "ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category saved', style: TextStyle(fontFamily: 'Tajawal'))));\n    await widget.onChanged();"
if old2 in t:
    t = t.replace(old2, new2, 1)
    print('pop fixed')
else:
    import re
    t2, n = re.subn(
        r'await widget\.onChanged\(\);\s*if \(context\.mounted\) Navigator\.pop\(context\);',
        "ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category saved', style: TextStyle(fontFamily: 'Tajawal'))));\n    await widget.onChanged();",
        t, count=1)
    print('regex n', n)
    t = t2
p.write_text(t)
print('size', p.stat().st_size)
