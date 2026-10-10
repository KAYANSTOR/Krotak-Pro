#!/usr/bin/env python3
"""الطبقة 1 — جرد آلي كامل للعناصر التفاعلية في lib/ui.

المخرج: docs/audit/interactive-inventory.csv
الأعمدة: file,line,element,label,handler

السكربت يحلّل نصّ Dart (تحليل بسيط بسطر واحد لكل عنصر) والغرض منه حصر
*كل* عنصر تفاعلي حتى لا يبقى أي عنصر بحالة «مجهول» في مصفوفة الأزرار
(القسم 5.4 من خطة التنفيذ النهائية). لا يُعدّ هذا السكربت إثباتاً سلوكياً —
الإثبات في الطبقات 2..4.
"""

from __future__ import annotations

import csv
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_DIR = os.path.join(ROOT, "lib", "ui")
OUT_DIR = os.path.join(ROOT, "docs", "audit")
OUT_FILE = os.path.join(OUT_DIR, "interactive-inventory.csv")

# المعالجات (callbacks) — كل سطر يحمل معالجاً يُعتبر عنصراً تفاعلياً.
CALLBACKS = (
    "onPressed",
    "onTap",
    "onLongPress",
    "onChanged",
    "onSubmitted",
    "onRefresh",
    "onSelected",
    "onDismissed",
    "onFieldSubmitted",
    "onDoubleTap",
)

# عناصر تفاعلية معروفة (بعضها يُعرّف المعالج على سطر آخر).
ELEMENTS = (
    "IconButton",
    "NetHeaderAction",
    "FloatingActionButton",
    "ListTile",
    "PopupMenuItem",
    "SettingsGroupNavRow",
    "TextButton",
    "FilledButton",
    "ElevatedButton",
    "OutlinedButton",
    "InkWell",
    "GestureDetector",
    "Dismissible",
    "Switch",
    "SwitchListTile",
    "Checkbox",
    "CheckboxListTile",
    "Radio",
    "RadioListTile",
    "DropdownButton",
    "Slider",
    "Tab",
    "TextFormField",
    "TextField",
)

TEXT_RE = re.compile(r"""(?:title|label|tooltip|hintText|semanticLabel)\s*:\s*(?:const\s+)?['"]([^'"]{1,80})['"]""")
TEXT_CHILD_RE = re.compile(r"""Text\(\s*(?:const\s+)?['"]([^'"]{1,80})['"]""")
ICON_RE = re.compile(r"""icon\s*:\s*(?:const\s+)?Icon\(\s*([A-Za-z0-9_.]+)""")
ICON_BUTTON_RE = re.compile(r"""IconButton\(\s*(?:const\s+)?icon\s*:\s*(?:const\s+)?Icon\(\s*([A-Za-z0-9_.]+)""")
HANDLER_RE = re.compile(r"""\b(""" + "|".join(CALLBACKS) + r""")\s*:""")
ELEMENT_RE = re.compile(r"""\b(""" + "|".join(ELEMENTS) + r""")\s*\(""")


def _label(line: str) -> str:
    for rx in (TEXT_RE, TEXT_CHILD_RE):
        m = rx.search(line)
        if m:
            return m.group(1)
    m = ICON_BUTTON_RE.search(line) or ICON_RE.search(line)
    if m:
        return "icon:" + m.group(1)
    return ""


def scan() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for dirpath, _dirnames, filenames in os.walk(UI_DIR):
        for name in sorted(filenames):
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            with io.open(path, encoding="utf-8") as handle:
                for number, raw in enumerate(handle, start=1):
                    line = raw.rstrip("\n")
                    cb = HANDLER_RE.search(line)
                    el = ELEMENT_RE.search(line)
                    if not cb and not el:
                        continue
                    rows.append(
                        {
                            "file": rel,
                            "line": str(number),
                            "element": el.group(1) if el else "",
                            "label": _label(line),
                            "handler": cb.group(1) if cb else "",
                        }
                    )
    return rows


def main() -> int:
    rows = scan()
    os.makedirs(OUT_DIR, exist_ok=True)
    with io.open(OUT_FILE, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=["file", "line", "element", "label", "handler"]
        )
        writer.writeheader()
        writer.writerows(rows)

    callbacks = sum(1 for r in rows if r["handler"])
    elements = sum(1 for r in rows if r["element"])
    files = len({r["file"] for r in rows})
    print(f"rows={len(rows)} callbacks={callbacks} elements={elements} files={files}")
    print(f"written: {os.path.relpath(OUT_FILE, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
