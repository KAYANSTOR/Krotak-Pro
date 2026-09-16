from pathlib import Path
p = Path('lib/ui/theme/net_theme.dart')
t = p.read_text()
# Remove stray J corruption
t = t.replace('FlexSchemeColor(J', 'FlexSchemeColor(')
# Remove google_fonts if present (incompatible with current Flutter)
t = t.replace("import 'package:google_fonts/google_fonts.dart';\n", '')
t = t.replace('GoogleFonts.tajawalTextTheme(base.textTheme).apply(', 'base.textTheme.apply(')
t = t.replace("fontFamily: 'Tajawal'", "fontFamily: 'Roboto'")
# Ensure high-contrast listTile and onSurface exist
if 'listTileTheme:' not in t:
    print('WARNING: listTileTheme missing - theme may be incomplete')
p.write_text(t)
print('repaired', p.stat().st_size)
print('has J corruption', 'FlexSchemeColor(J' in t)
print('has google_fonts', 'google_fonts' in t)
