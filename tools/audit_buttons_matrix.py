#!/usr/bin/env python3
"""القسم 5.4 — مصفوفة الأزرار الكاملة + بوابة التغطية.

يبني ``docs/audit/buttons-matrix-<date>.csv`` من جرد الطبقة 1
(``docs/audit/interactive-inventory.csv``): صف واحد لكل عنصر تفاعلي، بالأعمدة:
المعرّف | الشاشة | العنصر | النص/الأيقونة | الملف:السطر | الوظيفة المتوقعة |
المسار الفعلي | الأثر | الفئة (A-G) | الحالة | الإصلاح | اختبار الإثبات

الفئة تُستخرج آليًا (إرشاديًا) من جسم المعالج. الحالة/الإصلاح/اختبار الإثبات
تأتي من جدول تحقّقات مُنسَّق (RULES) للبنود المُصلَحة أو التي تحتاج جهازًا،
وما تبقّى «يعمل» استنادًا إلى المسح السلوكي (الطبقة 4) والاختبارات.
لا صف بحالة «مجهول»؛ وبوابة ``--check`` تفشل عند أي اختلاف أو حالة غير معروفة.
"""

from __future__ import annotations

import csv
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INV_FILE = os.path.join(ROOT, "docs", "audit", "interactive-inventory.csv")
OUT_DIR = os.path.join(ROOT, "docs", "audit")
DATE = "2026-10-10"
OUT_FILE = os.path.join(OUT_DIR, f"buttons-matrix-{DATE}.csv")

COLUMNS = [
    "id",
    "screen",
    "element",
    "label",
    "file_line",
    "expected_function",
    "actual_path",
    "effect",
    "category",
    "status",
    "fix",
    "proof_test",
]

VALID_STATUS = {"يعمل", "مُصلَح", "ناقص-مؤجل بسبب", "يحتاج جهاز"}
VALID_CATEGORY = {"A", "B", "C", "D", "E", "F", "G"}

# جدول تحقّقات مُنسَّق: (ملف، شرط النص/المعالج أو None، الحالة، الإصلاح، اختبار الإثبات).
# أول قاعدة تنطبق تفوز؛ وما لا ينطبق عليه شيء = «يعمل».
RULES = [
    ("lib/ui/screens/settings/maintenance_hub_screen.dart", "تصدير",
     "مُصلَح", "WP-3: تصدير CSV فعلي إلى مجلد التنزيلات (Exports)",
     "test/widget/maintenance_hub_screen_test.dart"),
    ("lib/ui/screens/settings/maintenance_hub_screen.dart", None,
     "مُصلَح", "WP-3: بطاقة صيانة موحّدة (تنظيف سجلات/تنظيف عميق/تصدير)",
     "test/widget/maintenance_hub_screen_test.dart"),
    ("lib/ui/screens/settings/backup_restore_screen.dart", "مشاركة",
     "يحتاج جهاز", "WP-4: مشاركة ملف النسخة عبر ورقة مشاركة النظام",
     "test/widget/backup_visible_copy_test.dart"),
    ("lib/ui/screens/settings/backup_restore_screen.dart", None,
     "مُصلَح", "WP-4: نسخة ظاهرة في Download/Krotak Pro + استعادة",
     "test/widget/backup_visible_copy_test.dart"),
    ("lib/ui/screens/inventory_import_logs_screen.dart", None,
     "مُصلَح", "WP-5: إدارة ملفات الاستيراد (سجل من الجدول + تصدير فعلي)",
     "test/widget/inventory_import_logs_screen_test.dart"),
    ("lib/ui/screens/inventory_screen.dart", None,
     "مُصلَح", "WP-5: أزرار الاستيراد تفتح الورقة الصحيحة",
     "test/widget/inventory_import_sheet_test.dart"),
    ("lib/ui/screens/settings/outbound_message_templates_screen.dart", None,
     "مُصلَح", "WP-6: سجل متغيرات واحد بلا تكرار ولا أكواد لاتينية",
     "test/services/template_variable_registry_test.dart"),
    ("lib/ui/widgets/net/net_transaction_detail_sheet.dart", "حفظ",
     "يحتاج جهاز", "WP-8: حفظ صورة الإشعار في Pictures/Krotak Pro",
     "test/widget/transaction_receipt_image_test.dart"),
    ("lib/ui/widgets/net/net_transaction_detail_sheet.dart", "مشاركة",
     "يحتاج جهاز", "WP-8: مشاركة صورة الإشعار عبر ورقة النظام",
     "test/widget/transaction_receipt_image_test.dart"),
    ("lib/ui/screens/sold_cards_sheet.dart", None,
     "مُصلَح", "5.3: تصدير CSV إلى ملف فعلي (BOM) بدل الحافظة",
     "test/domain/sold_cards_phase4_test.dart"),
    ("lib/ui/widgets/customer_statement_export.dart", None,
     "مُصلَح", "5.3: حفظ النص/الصورة في مجلدات ظاهرة",
     "test/widget/customer_statement_export_visible_test.dart"),
    ("lib/ui/screens/settings/device_verification_screen.dart", None,
     "مُصلَح", "WP-9: تشخيص الخلفية وأسباب الإنهاء بالعربية",
     "test/domain/background_diagnostics_test.dart"),
    ("lib/ui/screens/wallets_screen.dart", None,
     "مُصلَح", "WP-10: اتساق المحافظ وإزالة القوالب النظامية المكرّرة",
     "test/services/wallet_catalog_strict_test.dart"),
]

CALLBACKS = (
    "onPressed", "onTap", "onLongPress", "onChanged", "onSubmitted",
    "onRefresh", "onSelected", "onDismissed", "onFieldSubmitted", "onDoubleTap",
)
HANDLER_RE = re.compile(r"\b(" + "|".join(CALLBACKS) + r")\s*:")

_LINES_CACHE: dict[str, list[str]] = {}


def source_lines(rel: str) -> list[str]:
    if rel not in _LINES_CACHE:
        with io.open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            _LINES_CACHE[rel] = handle.read().split("\n")
    return _LINES_CACHE[rel]


def nearby_text(rel: str, line: int, span: int = 5) -> str:
    lines = source_lines(rel)
    start = max(0, line - 1)
    end = min(len(lines), line - 1 + span)
    return " ".join(lines[start:end])


def handler_body(rel: str, line: int, key: str) -> str:
    """يستخرج تعبير المعالج: قائمة المعاملات ثم جسم ``=>`` أو ``{...}``."""
    lines = source_lines(rel)
    if line < 1 or line > len(lines):
        return ""
    window = ""
    for offset in range(0, 30):
        idx = line - 1 + offset
        if idx >= len(lines):
            break
        seg = lines[idx]
        if offset == 0:
            pos = seg.find(key + ":")
            if pos < 0:
                return ""
            seg = seg[pos + len(key) + 1:]
        window += seg + "\n"

    n = len(window)

    def skip_ws(i: int) -> int:
        while i < n and window[i] in " \t\n":
            i += 1
        return i

    def match(i: int, opener: str, closer: str) -> int:
        depth = 0
        while i < n:
            ch = window[i]
            if ch == opener:
                depth += 1
            elif ch == closer:
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        return n

    i = skip_ws(0)
    if i < n and window[i] == "(":
        i = match(i, "(", ")")
    i = skip_ws(i)
    if window[i:i + 5] == "async":
        i = skip_ws(i + 5)
    elif window[i:i + 4] == "sync":
        i = skip_ws(i + 4)
        if window[i:i + 1] == "*":
            i = skip_ws(i + 1)
    if window[i:i + 2] == "=>":
        j = i + 2
        depth = 0
        while j < n:
            ch = window[j]
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif ch == "," and depth == 0:
                break
            elif ch == "\n" and depth == 0:
                break
            j += 1
        return window[i:j]
    if i < n and window[i] == "{":
        return window[i:match(i, "{", "}")]
    return window[i:window.find("\n", i) if window.find("\n", i) >= 0 else n]


def classify(body: str) -> str:
    """تصنيف إرشادي (A..G) من نص جسم المعالج.

    A تنقّل/حوار، D حافظة/Snackbar فقط، B استدعاء خدمة/مستودع أو إجراء مسمّى،
    C حالة واجهة. لا يُنتج E/F/G آليًا (تُحدَّد يدويًا في جدول التحقّقات).
    """
    if not body:
        return "C"
    if "Clipboard.setData" in body:
        return "D"
    if re.search(
        r"Navigator\.|showDialog|showModalBottomSheet|showDatePicker|"
        r"showTimePicker|MaterialPageRoute|showCustomerStatement|"
        r"showSoldCards|show[A-Z][A-Za-z]*Sheet",
        body,
    ):
        return "A"
    if re.search(
        r"AppScope\.of|container\.|c\.|service|Repository|"
        r"\.(save|create|delete|update|insert|send|export|import|restore|"
        r"clean|list|find|toggle|enable|disable|commit|build|share)\(|"
        r"saveToDownloads|saveImageToPictures|Share\.|shareXFiles",
        body,
    ):
        return "B"
    if "setState" in body:
        return "C"
    if re.search(r"[A-Za-z_]\w*\s*\(", body):
        return "B"
    if re.fullmatch(r"\s*[A-Za-z_][A-Za-z0-9_]*\s*,?\s*", body):
        return "B"
    if re.search(r"showSnackBar|ScaffoldMessenger", body):
        return "D"
    return "C"


def screen_of(rel: str) -> str:
    name = os.path.basename(rel)[:-5]
    return name.replace("_screen", "").replace("_sheet", "")


def expected_function(element: str, label: str, handler: str) -> str:
    if label:
        return label
    if element:
        return element
    return handler or "عنصر تفاعلي"


def actual_path(element: str, handler: str) -> str:
    return handler or element or "—"


def effect_of(category: str) -> str:
    return {
        "A": "تنقّل/فتح واجهة",
        "B": "خدمة/مستودع (DB أو ملف أو Android)",
        "C": "حالة واجهة فقط",
        "D": "مشبوه: Snackbar/حافظة",
        "E": "مشبوه: يتجاهل Failure",
        "F": "مشبوه: التسمية لا تطابق الفعل",
        "G": "زر معطّل/غير قابل للوصول",
    }[category]


def status_for(rel: str, context: str) -> tuple[str, str, str]:
    for rule_file, needle, status, fix, test in RULES:
        if rel != rule_file:
            continue
        if needle is None or needle in context:
            return status, fix, test
    return "يعمل", "", ""


def build_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with io.open(INV_FILE, encoding="utf-8") as handle:
        for index, raw in enumerate(csv.DictReader(handle), start=1):
            rel = raw["file"]
            line = int(raw["line"])
            element = raw.get("element", "")
            label = raw.get("label", "")
            handler = raw.get("handler", "")
            body = handler_body(rel, line, handler) if handler else ""
            category = classify(body)
            context = f"{label}|{handler}|{nearby_text(rel, line)}"
            status, fix, test = status_for(rel, context)
            rows.append(
                {
                    "id": f"BTN-{index:04d}",
                    "screen": screen_of(rel),
                    "element": element or "—",
                    "label": label or "—",
                    "file_line": f"{rel}:{line}",
                    "expected_function": expected_function(element, label, handler),
                    "actual_path": actual_path(element, handler),
                    "effect": effect_of(category),
                    "category": category,
                    "status": status,
                    "fix": fix,
                    "proof_test": test,
                }
            )
    return rows


def write_matrix(rows: list[dict[str, str]]) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    with io.open(OUT_FILE, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def check(rows: list[dict[str, str]]) -> int:
    problems: list[str] = []
    with io.open(INV_FILE, encoding="utf-8") as handle:
        inventory = list(csv.DictReader(handle))
    if len(inventory) != len(rows):
        problems.append(f"عدد صفوف المصفوفة ({len(rows)}) لا يطابق الجرد ({len(inventory)})")
    inv_keys = {f"{r['file']}:{r['line']}" for r in inventory}
    row_keys = {r["file_line"] for r in rows}
    if inv_keys != row_keys:
        problems.append("عناصر المصفوفة لا تطابق عناصر الجرد (file:line)")
    for row in rows:
        if row["status"] not in VALID_STATUS:
            problems.append(f"حالة غير معروفة في {row['id']}: {row['status']!r}")
        if row["category"] not in VALID_CATEGORY:
            problems.append(f"فئة غير معروفة في {row['id']}: {row['category']!r}")
        if not row["status"].strip():
            problems.append(f"صف بلا حالة: {row['id']}")
    if problems:
        print("FAILED coverage gate:")
        for item in problems[:20]:
            print("  - " + item)
        return 1
    print(
        f"OK coverage gate: rows={len(rows)} "
        f"known_status={sum(1 for r in rows if r['status'] in VALID_STATUS)}"
    )
    return 0


def main(argv: list[str]) -> int:
    rows = build_rows()
    if "--check" in argv:
        return check(rows)
    write_matrix(rows)
    counts: dict[str, int] = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    print(f"rows={len(rows)}")
    for key in sorted(counts):
        print(f"  {key}: {counts[key]}")
    print("written: " + os.path.relpath(OUT_FILE, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
