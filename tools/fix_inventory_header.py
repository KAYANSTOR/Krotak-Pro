#!/usr/bin/env python3
from pathlib import Path
p = Path("lib/ui/screens/inventory_widgets.dart")
t = p.read_text()
old = """        children: [
          _RoundIcon(icon: Icons.more_horiz, onTap: onMenu),
          const SizedBox(width: 8),
          _RoundIcon(icon: Icons.add, onTap: onAdd),
          const SizedBox(width: 8),
          _RoundIcon(icon: Icons.delete_outline, onTap: onDelete),
          const Spacer(),
          const Text(
            'إدارة الكروت',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: KayanColors.textPrimary,
            ),
          ),
        ],"""
new = """        children: [
          // RTL: first child = right side → title on the right
          const Text(
            'إدارة الكروت',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: KayanColors.textPrimary,
            ),
          ),
          const Spacer(),
          // From right to left after title: archive, add, menu
          _RoundIcon(icon: Icons.delete_outline, onTap: onDelete),
          const SizedBox(width: 8),
          _RoundIcon(icon: Icons.add, onTap: onAdd),
          const SizedBox(width: 8),
          _RoundIcon(icon: Icons.more_horiz, onTap: onMenu),
        ],"""
if old not in t:
    print("pattern not found")
    i = t.find("_RoundIcon(icon: Icons.more_horiz")
    print(repr(t[i:i+400]) if i>=0 else "no more_horiz")
    raise SystemExit(1)
p.write_text(t.replace(old, new, 1))
print("header RTL fixed")
assert "first child = right side" in p.read_text()
